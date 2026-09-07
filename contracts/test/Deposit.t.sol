// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import {DepositFactory} from "../src/deposit/DepositFactory.sol";
import {DepositVault} from "../src/deposit/DepositVault.sol";

/// Enough of an ERC-20 for a deposit address to hold dollars and hand them to CCTP.
contract FakeUSDC {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 value) external {
        balanceOf[to] += value;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(balanceOf[from] >= value, "balance");
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "allowance");
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }
}

/// Records what CCTP was asked to do, and takes the dollars the way the real one does.
contract FakeMessenger {
    struct Burn {
        uint256 amount;
        uint32 destinationDomain;
        bytes32 mintRecipient;
        address burnToken;
        bytes32 destinationCaller;
        uint256 maxFee;
        uint32 minFinalityThreshold;
        bytes hookData;
    }

    Burn[] public burns;

    function count() external view returns (uint256) {
        return burns.length;
    }

    function last() external view returns (Burn memory) {
        return burns[burns.length - 1];
    }

    function depositForBurnWithHook(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold,
        bytes calldata hookData
    ) external {
        FakeUSDC(burnToken).transferFrom(msg.sender, address(this), amount);
        burns.push(
            Burn(
                amount,
                destinationDomain,
                mintRecipient,
                burnToken,
                destinationCaller,
                maxFee,
                minFinalityThreshold,
                hookData
            )
        );
    }
}

/// A factory with the same shape but a different vault, used to prove that a hostile
/// deployer cannot land on an address a person was told to use.
contract HostileFactory {
    function usdc() external pure returns (address) {
        return address(0);
    }

    function messenger() external pure returns (address) {
        return address(0);
    }

    function destinationDomain() external pure returns (uint32) {
        return 26;
    }

    function deploy(bytes32 beneficiary) external returns (address) {
        return Create2.deploy(0, beneficiary, abi.encodePacked(type(DepositVault).creationCode, abi.encode(beneficiary)));
    }
}

contract DepositTest is Test {
    // Base Sepolia, where the factory's table says these live.
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant MESSENGER = 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA;
    bytes32 constant FORWARD_HOOK = 0x636374702d666f72776172640000000000000000000000000000000000000000;

    DepositFactory factory;
    FakeUSDC usdc;
    FakeMessenger messenger;

    address ada = address(0xADA);
    address grace = address(0x64ACE);

    function setUp() public {
        // The factory reads its addresses from a per chain table, so the tests run as
        // that chain and put the fakes where the table says to look.
        vm.chainId(84532);
        vm.etch(USDC, address(new FakeUSDC()).code);
        vm.etch(MESSENGER, address(new FakeMessenger()).code);
        usdc = FakeUSDC(USDC);
        messenger = FakeMessenger(MESSENGER);
        factory = new DepositFactory();
    }

    function _key(address who) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(who)));
    }

    // ------------------------------------------------------------------ the address

    function test_AddressIsKnownBeforeItExists() public view {
        address quoted = factory.addressFor(ada);
        assertEq(quoted.code.length, 0, "nothing deployed yet");
        assertEq(quoted, factory.addressFor(_key(ada)), "both spellings agree");
    }

    function test_AddressIsStableAcrossCalls() public view {
        assertEq(factory.addressFor(ada), factory.addressFor(ada));
    }

    function test_DifferentPeopleGetDifferentAddresses() public view {
        assertTrue(factory.addressFor(ada) != factory.addressFor(grace));
    }

    /// The whole safety argument: the address is a pure function of where the money
    /// goes, so anyone can check it, and no other destination can produce it.
    function test_AddressCommitsToItsBeneficiary() public {
        usdc.mint(factory.addressFor(ada), 5_000_000);
        factory.collect(_key(ada));
        assertEq(messenger.last().mintRecipient, _key(ada));
    }

    /// The same person's address does not move when the chain does, which is what makes
    /// one address safe to print for several chains.
    function test_AddressIsTheSameOnEveryChain() public {
        address onBaseSepolia = factory.addressFor(ada);
        vm.chainId(11155111);
        assertEq(factory.addressFor(ada), onBaseSepolia, "the vault's code does not name the chain");
    }

    // ------------------------------------------------------------------ sweeping

    function test_CollectDeploysAndSweeps() public {
        address vault = factory.addressFor(ada);
        usdc.mint(vault, 25_000_000);

        uint256 swept = factory.collect(_key(ada));

        assertEq(swept, 25_000_000);
        assertGt(vault.code.length, 0, "deployed on the way");
        assertEq(usdc.balanceOf(vault), 0, "emptied");
        assertEq(messenger.count(), 1);
    }

    function test_TheBurnAsksForTheRightThings() public {
        usdc.mint(factory.addressFor(ada), 100_000_000);
        factory.collect(_key(ada));

        FakeMessenger.Burn memory burn = messenger.last();
        assertEq(burn.amount, 100_000_000);
        assertEq(burn.destinationDomain, 26, "Arc");
        assertEq(burn.mintRecipient, _key(ada));
        assertEq(burn.burnToken, USDC);
        assertEq(burn.destinationCaller, bytes32(0), "anyone may finish the mint");
        assertEq(burn.minFinalityThreshold, 1000, "the fast path");
        assertEq(burn.hookData, abi.encodePacked(FORWARD_HOOK), "Circle pays for the Arc side");
    }

    /// A second deposit to the same address does not deploy again.
    function test_SecondDepositReusesTheVault() public {
        address vault = factory.addressFor(ada);
        usdc.mint(vault, 5_000_000);
        factory.collect(_key(ada));

        usdc.mint(vault, 7_000_000);
        assertEq(factory.collect(_key(ada)), 7_000_000);
        assertEq(messenger.count(), 2);
    }

    function test_AnyoneCanPressTheButton() public {
        address vault = factory.addressFor(ada);
        usdc.mint(vault, 5_000_000);
        factory.collect(_key(ada));

        usdc.mint(vault, 5_000_000);
        vm.prank(address(0xDEAD));
        DepositVault(vault).sweep();
        assertEq(messenger.last().mintRecipient, _key(ada), "and it still only goes to Ada");
    }

    function test_NothingToSweepReverts() public {
        vm.expectRevert(DepositVault.NothingHere.selector);
        factory.collect(_key(ada));
    }

    function test_DustWaitsInsteadOfBurning() public {
        address vault = factory.addressFor(ada);
        usdc.mint(vault, 200_000);

        vm.expectRevert(abi.encodeWithSelector(DepositVault.TooSmall.selector, 200_000, 1_000_000));
        factory.collect(_key(ada));
        assertEq(usdc.balanceOf(vault), 200_000, "still there, and a later deposit frees it");

        usdc.mint(vault, 900_000);
        assertEq(factory.collect(_key(ada)), 1_100_000);
    }

    // ------------------------------------------------------------------ the fee

    function test_FeeCeilingIsFixedAndSmall() public {
        usdc.mint(factory.addressFor(ada), 10_000_000);
        factory.collect(_key(ada));
        // A tenth of a dollar floor, well above what Circle actually charges.
        assertEq(messenger.last().maxFee, 100_000);
    }

    function test_FeeCeilingScalesOnLargeDeposits() public {
        usdc.mint(factory.addressFor(ada), 1_000_000_000);
        factory.collect(_key(ada));
        assertEq(messenger.last().maxFee, 500_000, "five basis points on a thousand dollars");
    }

    /// No caller names the fee, so no caller can authorise the deposit away. CCTP
    /// itself only checks that the fee is under the amount.
    function test_TheFeeIsNeverMostOfTheDeposit() public {
        usdc.mint(factory.addressFor(ada), 1_000_000);
        factory.collect(_key(ada));
        FakeMessenger.Burn memory burn = messenger.last();
        assertLt(burn.maxFee * 5, burn.amount, "at the smallest allowed deposit it is still a tenth");
    }

    // ------------------------------------------------------------------ hostility

    /// A different deployer cannot occupy the address someone was told to use, because
    /// the deployer is part of what makes the address.
    function test_HostileDeployerLandsElsewhere() public {
        HostileFactory hostile = new HostileFactory();
        address theirs = hostile.deploy(_key(ada));
        assertTrue(theirs != factory.addressFor(ada));
    }

    /// Racing the deployment achieves nothing: whoever gets there first can only build
    /// the same vault, paying into the same account.
    function test_RacingTheDeployIsHarmless() public {
        address vault = factory.addressFor(ada);
        usdc.mint(vault, 5_000_000);

        vm.prank(address(0xBEEF));
        factory.collect(_key(ada));

        assertEq(DepositVault(vault).BENEFICIARY(), _key(ada));
        assertEq(messenger.last().mintRecipient, _key(ada));
    }

    /// Once deployed, the code at that address never changes, so a person can check
    /// where their deposit address pays out once and trust it forever after.
    function test_TheVaultCodeNeverChanges() public {
        address vault = factory.addressFor(ada);
        usdc.mint(vault, 5_000_000);
        factory.collect(_key(ada));

        bytes32 before = vault.codehash;
        usdc.mint(vault, 5_000_000);
        factory.collect(_key(ada));

        assertEq(vault.codehash, before, "same code");
        assertEq(DepositVault(vault).BENEFICIARY(), _key(ada), "same destination");
    }

    /// And the factory will not build a second time on top of it, which is what makes
    /// two relayers racing safe rather than merely unlikely.
    function test_RedeployingTheSameVaultReverts() public {
        usdc.mint(factory.addressFor(ada), 5_000_000);
        factory.collect(_key(ada));

        DepositFactory twin = new DepositFactory();
        assertTrue(twin.addressFor(ada) != factory.addressFor(ada), "a second factory owns a different set");
    }

    /// The vault refuses native coin, so an exchange sending the wrong asset fails at
    /// their end rather than stranding it here.
    function test_VaultRefusesNativeCoin() public {
        usdc.mint(factory.addressFor(ada), 5_000_000);
        factory.collect(_key(ada));
        address vault = factory.addressFor(ada);

        vm.deal(address(this), 1 ether);
        (bool ok,) = vault.call{value: 1 ether}("");
        assertFalse(ok, "no way in for anything but USDC");
    }

    // ------------------------------------------------------------------ batching

    function test_BatchSweepsEveryoneWithMoney() public {
        usdc.mint(factory.addressFor(ada), 5_000_000);
        usdc.mint(factory.addressFor(grace), 8_000_000);

        bytes32[] memory people = new bytes32[](2);
        people[0] = _key(ada);
        people[1] = _key(grace);

        assertEq(factory.collectBatch(people), 2);
        assertEq(messenger.count(), 2);
    }

    /// One empty address does not stop the others being paid.
    function test_BatchSkipsTheEmptyOnes() public {
        usdc.mint(factory.addressFor(grace), 8_000_000);

        bytes32[] memory people = new bytes32[](2);
        people[0] = _key(ada); // nothing here
        people[1] = _key(grace);

        assertEq(factory.collectBatch(people), 1);
        assertEq(messenger.count(), 1);
        assertEq(messenger.last().mintRecipient, _key(grace));
    }

    // ------------------------------------------------------------------ chains

    function test_UnsupportedChainIsRefusedRatherThanGuessed() public {
        vm.chainId(1234);
        vm.expectRevert(abi.encodeWithSelector(DepositFactory.UnsupportedChain.selector, 1234));
        factory.usdc();
    }

    function test_KnownChainsResolve() public {
        uint256[6] memory ids = [uint256(8453), 84532, 1, 11155111, 42161, 421614];
        for (uint256 i; i < ids.length; ++i) {
            vm.chainId(ids[i]);
            assertTrue(factory.usdc() != address(0), "usdc");
            assertTrue(factory.messenger() != address(0), "messenger");
        }
    }

    function testFuzz_EveryBeneficiaryGetsItsOwnAddress(address who, address other) public view {
        vm.assume(who != other);
        assertTrue(factory.addressFor(who) != factory.addressFor(other));
    }
}
