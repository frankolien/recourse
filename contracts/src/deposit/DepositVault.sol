// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ITokenMessengerV2, IERC20Minimal, IDepositConfig} from "./IDepositBridge.sol";

/// @title DepositVault
/// @notice The address a person is told to send USDC to, on a chain that is not Arc.
///
/// It has exactly one power: burn the USDC it holds into a CCTP message addressed to
/// one Arc account. That account is a constructor argument, so it is part of the code
/// this contract is deployed from, and therefore part of the address itself. Nobody can
/// point it somewhere else, including whoever deploys it, because a different
/// destination is a different address.
///
/// There is no owner, no rescue, no upgrade and no way out. That is the point: the
/// person is being asked to send money to an address nobody controls, and the only
/// honest way to make that safe is for the address to have no other behaviour.
contract DepositVault {
    /// The Arc account this address pays into, as CCTP carries a recipient.
    bytes32 public immutable BENEFICIARY;

    /// Set from the deployer rather than an argument, so it never reaches the creation
    /// code and the vault's address stays the same on every chain.
    IDepositConfig public immutable FACTORY;

    /// Circle's forwarding service. With this hook in the message Circle pays for the
    /// mint on Arc, so a deposit needs no transaction on Arc and no gas there at all.
    bytes32 private constant FORWARD_HOOK = 0x636374702d666f72776172640000000000000000000000000000000000000000;

    /// Ask for the fast path. Below 1000 CCTP attests in seconds for a fee; at 2000 it
    /// is free and waits for hard finality.
    uint32 private constant FAST_FINALITY = 1000;

    /// What the burn may authorise Circle to keep. Fixed in code, not taken from the
    /// caller, because CCTP bounds the fee only by `maxFee < amount`: a vault that let
    /// its caller name this figure would let a careless or hostile relayer authorise
    /// away the whole deposit. Circle quotes Base to Arc at well under a basis point
    /// plus about two cents to forward, so the ceiling here is several times the real
    /// price. It is set high on purpose, because a quote that has drifted above it does
    /// not fail loudly, it silently downgrades the transfer to the slow path.
    uint256 private constant FEE_BPS = 5;
    uint256 private constant FEE_FLOOR = 100_000;

    /// A deposit has to be worth more than it costs to move, with enough left over that
    /// the remainder is not an insult. Below this the money waits, and any later
    /// deposit to the same address releases both.
    uint256 public constant MIN_DEPOSIT = 1_000_000;

    error NothingHere();
    error TooSmall(uint256 held, uint256 needed);

    event Swept(bytes32 indexed beneficiary, uint256 amount, uint256 maxFee);

    constructor(bytes32 beneficiary) {
        BENEFICIARY = beneficiary;
        FACTORY = IDepositConfig(msg.sender);
    }

    /// Send whatever USDC is here to Arc.
    ///
    /// Open to anyone on purpose. The destination is welded into this contract, so
    /// letting the world press the button costs nothing and takes Recourse out of the
    /// path: if we vanish tomorrow, a stranger can still move this money, and only to
    /// the person it belongs to.
    function sweep() external returns (uint256 amount) {
        address token = FACTORY.usdc();
        address bridge = FACTORY.messenger();

        amount = IERC20Minimal(token).balanceOf(address(this));
        if (amount == 0) revert NothingHere();
        if (amount < MIN_DEPOSIT) revert TooSmall(amount, MIN_DEPOSIT);

        uint256 maxFee = (amount * FEE_BPS) / 10_000;
        if (maxFee < FEE_FLOOR) maxFee = FEE_FLOOR;

        // Approving once for everything this address will ever hold: the allowance is
        // to Circle's own contract, and this vault can do nothing with it but burn.
        if (IERC20Minimal(token).allowance(address(this), bridge) < amount) {
            IERC20Minimal(token).approve(bridge, type(uint256).max);
        }

        ITokenMessengerV2(bridge).depositForBurnWithHook(
            amount,
            FACTORY.destinationDomain(),
            BENEFICIARY,
            token,
            // Left open so anyone may complete the mint. This is what lets Circle's
            // forwarder do it, and what lets somebody else finish a stuck one.
            bytes32(0),
            maxFee,
            FAST_FINALITY,
            abi.encodePacked(FORWARD_HOOK)
        );

        emit Swept(BENEFICIARY, amount, maxFee);
    }

    /// No receive and no payable fallback, deliberately. Once this contract exists an
    /// exchange sending native coin here fails visibly at their end, which is a far
    /// better outcome for the person than the money arriving somewhere it can never
    /// leave.
}
