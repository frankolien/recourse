// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {P256Owner} from "../src/P256Owner.sol";
import {P256OwnerFactory} from "../src/P256OwnerFactory.sol";

// Forge's EVM has no P-256 precompile, so a real verifier (Daimo's, as deployed on Arc)
// is placed at 0x100 to play the precompile, and at a second address to play the
// fallback. Both are the same bytecode; what differs is which path the owner takes.
contract P256OwnerTest is Test {
    bytes4 constant MAGIC_HASH = 0x1626ba7e;
    bytes4 constant MAGIC_BYTES = 0x20c13b0b;
    bytes4 constant NOT_VALID = 0xffffffff;

    address constant PRECOMPILE = address(0x100);
    address constant FALLBACK = address(0xFA11BAC);

    // RIP-7212 specification vector.
    bytes32 constant SPEC_HASH = 0x4cee90eb86eaa050036147a12d49004b6b9c72bd725d39d4785011fe190f0b4d;
    bytes32 constant SPEC_R = 0xa73bd4903f0ce3b639bbbf6e8e80d16931ff4bcf5993d58468e8fb19086e8cac;
    bytes32 constant SPEC_S = 0x36dbcd03009df8c59286b162af3bd7fcc0450c9aa81be5d10d312af6c66b1d60;
    uint256 constant SPEC_X = 0x4aebd3099c618202fcfe16ae7770b0c49ab5eadf74b754204a3bb6060e44eff3;
    uint256 constant SPEC_Y = 0x7618b065f9832de4ca6ca971a7a1adc826d0f7c00181a5fb2ddf79ae00b4e10e;

    // A key generated with openssl, signing the keccak of DEVICE_DATA the way the
    // Secure Enclave will: over the digest directly, no second hash.
    uint256 constant DEVICE_X = 0xf299ff7835b561210fb5fd3cd59c45500b84d05ba8579b8ce2687ecf8429f876;
    uint256 constant DEVICE_Y = 0x029e61bc9fe4f56c2e7638c3b49a21f83d859f0e59efd13ebdd68dcf773397c2;
    bytes constant DEVICE_DATA = hex"19010000000000000000000000000000000000000000000000000000000000000000ab";
    bytes32 constant DEVICE_R = 0x714ab0439a1070b8c4fa9e73bfd14084b77353b4ba13136e3ae5155a01c81db0;
    bytes32 constant DEVICE_S = 0x5af1cf184fc48e7ec0c00f01c51e3f8d11c3cd05965a2bd117a5dde06937b488;

    bytes verifierCode;
    P256OwnerFactory factory;

    function setUp() public {
        verifierCode = vm.parseBytes(vm.trim(vm.readFile("test/fixtures/daimo-p256-verifier.hex")));
        vm.etch(PRECOMPILE, verifierCode);
        vm.etch(FALLBACK, verifierCode);
        factory = new P256OwnerFactory(FALLBACK);
    }

    function _sig(bytes32 r, bytes32 s) internal pure returns (bytes memory) {
        return abi.encodePacked(r, s);
    }

    function test_acceptsTheSpecificationVector() public {
        P256Owner owner = P256Owner(factory.create(SPEC_X, SPEC_Y));
        assertEq(owner.isValidSignature(SPEC_HASH, _sig(SPEC_R, SPEC_S)), MAGIC_HASH);
    }

    function test_bytesOverloadSignsTheKeccakOfThePreimage() public {
        P256Owner owner = P256Owner(factory.create(DEVICE_X, DEVICE_Y));
        assertEq(owner.isValidSignature(DEVICE_DATA, _sig(DEVICE_R, DEVICE_S)), MAGIC_BYTES);
        // The same signature is over keccak(DEVICE_DATA), so it also passes as a hash.
        assertEq(owner.isValidSignature(keccak256(DEVICE_DATA), _sig(DEVICE_R, DEVICE_S)), MAGIC_HASH);
    }

    function test_rejectsASignatureOverADifferentHash() public {
        P256Owner owner = P256Owner(factory.create(SPEC_X, SPEC_Y));
        bytes32 other = bytes32(uint256(SPEC_HASH) ^ 1);
        assertEq(owner.isValidSignature(other, _sig(SPEC_R, SPEC_S)), NOT_VALID);
    }

    function test_rejectsATamperedSignature() public {
        P256Owner owner = P256Owner(factory.create(SPEC_X, SPEC_Y));
        bytes32 s = bytes32(uint256(SPEC_S) ^ 1);
        assertEq(owner.isValidSignature(SPEC_HASH, _sig(SPEC_R, s)), NOT_VALID);
    }

    function test_rejectsAnotherKeysSignature() public {
        P256Owner owner = P256Owner(factory.create(DEVICE_X, DEVICE_Y));
        assertEq(owner.isValidSignature(SPEC_HASH, _sig(SPEC_R, SPEC_S)), NOT_VALID);
    }

    function test_refusesAnythingButRAndS() public {
        P256Owner owner = P256Owner(factory.create(SPEC_X, SPEC_Y));
        bytes memory withRecoveryId = abi.encodePacked(SPEC_R, SPEC_S, uint8(27));
        vm.expectRevert(abi.encodeWithSelector(P256Owner.BadSignatureLength.selector, uint256(65)));
        owner.isValidSignature(SPEC_HASH, withRecoveryId);
    }

    // The precompile answers an invalid signature and a missing precompile the same
    // way, with nothing. Both must reach the fallback, and the fallback decides.
    function test_fallsBackWhenThePrecompileAnswersEmpty() public {
        vm.etch(PRECOMPILE, "");
        P256Owner owner = P256Owner(factory.create(SPEC_X, SPEC_Y));
        assertEq(owner.isValidSignature(SPEC_HASH, _sig(SPEC_R, SPEC_S)), MAGIC_HASH);
        assertEq(owner.isValidSignature(bytes32(uint256(SPEC_HASH) ^ 1), _sig(SPEC_R, SPEC_S)), NOT_VALID);
    }

    function test_withoutAFallbackAnEmptyPrecompileMeansInvalid() public {
        vm.etch(PRECOMPILE, "");
        P256OwnerFactory bare = new P256OwnerFactory(address(0));
        P256Owner owner = P256Owner(bare.create(SPEC_X, SPEC_Y));
        assertEq(owner.isValidSignature(SPEC_HASH, _sig(SPEC_R, SPEC_S)), NOT_VALID);
    }

    function test_factoryAddressIsKnownBeforeDeployment() public {
        address predicted = factory.getAddress(DEVICE_X, DEVICE_Y);
        assertEq(predicted.code.length, 0);
        assertEq(factory.create(DEVICE_X, DEVICE_Y), predicted);
        assertGt(predicted.code.length, 0);
        assertEq(P256Owner(predicted).x(), DEVICE_X);
        assertEq(P256Owner(predicted).y(), DEVICE_Y);
        assertEq(P256Owner(predicted).fallbackVerifier(), FALLBACK);
    }

    function test_creatingTwiceReturnsTheSameOwner() public {
        address first = factory.create(DEVICE_X, DEVICE_Y);
        address second = factory.create(DEVICE_X, DEVICE_Y);
        assertEq(first, second);
    }

    function test_differentKeysGetDifferentOwners() public {
        assertTrue(factory.getAddress(DEVICE_X, DEVICE_Y) != factory.getAddress(SPEC_X, SPEC_Y));
    }
}
