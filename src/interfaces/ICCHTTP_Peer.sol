//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CCHTTP_Types} from "../CCHTTP_Types.sol";

interface ICCHTTP_Peer {
     
    function updateSupplyRequest(
        CCHTTP_Types.updateSupplyParams memory params
    ) external returns (bool);

    function deployAndMintRequest(
        CCHTTP_Types.deployAndMintParams memory params
    ) external returns (bool);
    
    function getFeesForDeployAndMint(
        CCHTTP_Types.deployAndMintParams memory params
    ) external view returns (uint256, uint256);

    function getFeesForUpdateSupply(
        CCHTTP_Types.updateSupplyParams memory params
    ) external view returns (uint256 feeAmount);
}