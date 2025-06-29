// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.29;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IPoolV1} from "@chainlink/contracts-ccip/contracts/interfaces/IPool.sol";
import {IRMN} from "@chainlink/contracts-ccip/contracts/interfaces/IRMN.sol";
import {IRouter} from "@chainlink/contracts-ccip/contracts/interfaces/IRouter.sol";

import { Pool } from "@chainlink/contracts-ccip/contracts/libraries/Pool.sol";

import {IBurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MinimalBnMPool
 * @notice A minimal implementation of a BurnMint pool for a specific ERC20 token.
 * @dev To be called by Chainlink CCIP-CCT stack on cross-chain transactions.
 * This contract is designed to be small and low gas cost, and be deployed on demand.
 */

contract MinimalBnMPool is IPoolV1 {

    event Burned(address indexed receiver, uint256 amount);
    event Minted(address indexed receiver, uint256 amount);

    event Debug(string message);
    event DebugBytes(string message, bytes data);

    address public owner;
    IERC20 public token;

    address public routerAddress;
    address public rmnAddress;

    mapping(uint64 chain => address onRamp) public onRamp;

    constructor(address _tokenAddress, address factory) {
        owner = factory;
        token = IERC20(_tokenAddress);
    }

    function init(
        address _routerAddress,
        address _rmnAddress
    ) external {
        require(msg.sender == owner, "Not the owner");
        routerAddress = _routerAddress;
        rmnAddress = _rmnAddress;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    function isSupportedChain(
        uint64 remoteChainSelector
    ) external view override returns (bool) {
        // Check if the onRamp for the given remote chain selector is set
        return onRamp[remoteChainSelector] != address(0);
    }

    function isSupportedToken(
        address localToken
    ) external view override returns (bool) {
        // Check if the local token is the same as the token managed by this pool
        return localToken == address(token);
    }

    function enableRemoteChain(
        uint64 remoteChainSelector
    ) external onlyOwner {
        require(onRamp[remoteChainSelector] == address(0), "Remote chain already enabled");
        
        // Set the onRamp and offRamp addresses for the remote chain
        onRamp[remoteChainSelector] = IRouter(routerAddress).getOnRamp(remoteChainSelector);
    }

    //lockOrBurn
    function lockOrBurn(
        Pool.LockOrBurnInV1 calldata params
    ) external override returns (Pool.LockOrBurnOutV1 memory) {
        require(params.localToken == address(token), "Invalid token");
        require(msg.sender == onRamp[params.remoteChainSelector], "Not the onRamp address for this chain");

        if (   IRMN(rmnAddress).isCursed(  bytes16( uint128(params.remoteChainSelector) )  )   ){
             revert("Cursed by RMN");
        }
        address receiver = abi.decode(params.receiver, (address));
        // Burn the tokens
        IBurnMintERC20(address(token)).burn(
            params.amount
        );
        // Emit an event for the burn action
        emit Burned(receiver, params.amount);

        // Return a dummy bytes32 value as a placeholder
        return Pool.LockOrBurnOutV1({
            destTokenAddress: abi.encode(address(token) ), // hyperTokens, EVM predictable address shared in all chains
            destPoolData: bytes("") // Placeholder, as we don't have any specific pool data
        });
    }

    function releaseOrMint(
        Pool.ReleaseOrMintInV1 calldata params
    ) external override returns (Pool.ReleaseOrMintOutV1 memory) {
        require(params.localToken == address(token), "Invalid token");
        require(
            onRamp[params.remoteChainSelector] != address(0),
            "Remote chain not enabled"
        );
        require(
            IRouter(routerAddress).isOffRamp(
                params.remoteChainSelector,
                msg.sender
            ),
            "Not the offRamp address for this chain"
        );
        address srcPoolAddress = abi.decode(
            params.sourcePoolAddress,
            (address)
        );
        require(
            srcPoolAddress == address(this),
            "Invalid source pool address"
        );
        // Mint the tokens to the receiver
        IBurnMintERC20(address(token)).mint(
            params.receiver,
            params.amount
        );
        // Emit an event for the mint action
        emit Minted(params.receiver, params.amount);

        // Return the amount of tokens minted
        return Pool.ReleaseOrMintOutV1({
            destinationAmount: params.amount
        });
    }

    //IERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public pure  override returns (bool) {
        return (interfaceId == Pool.CCIP_POOL_V1 || interfaceId == type(IPoolV1).interfaceId || interfaceId == type(IERC165).interfaceId);
    }
    
}