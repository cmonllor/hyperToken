//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IPoolV1} from "@chainlink/contracts-ccip/contracts/interfaces/IPool.sol";

import { Pool } from "@chainlink/contracts-ccip/contracts/libraries/Pool.sol";


interface IMinimalBnMPool is IPoolV1 {
    event Burned(address indexed receiver, uint256 amount);
    event Minted(address indexed receiver, uint256 amount);
    event Debug(string message);
    event DebugBytes(string message, bytes data);

    function init(
        address _routerAddress,
        address _rmnAddress
    ) external;

    function enableRemoteChain(
        uint64 remoteChainSelector
    ) external;

    function isSupportedChain(
        uint64 remoteChainSelector
    ) external view returns (bool);

    function lockOrBurn(
        Pool.LockOrBurnInV1 calldata params
    ) external returns (Pool.LockOrBurnOutV1 memory);


    function releaseOrMint(
        Pool.ReleaseOrMintInV1 calldata params
    ) external returns (Pool.ReleaseOrMintOutV1 memory);

}