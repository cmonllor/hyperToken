//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "../CCHTTP_Types.sol";

interface ICCHTTP_Consumer{
    function DeployAndMintReceived(
        uint64 chain,
        CCHTTP_Types.deploy_and_mint_mssg memory params
    ) external returns (bool);

    function DeployAndMintConfirmed(
        uint64 chain,
        CCHTTP_Types.deploy_and_mint_mssg memory params
    ) external returns (bool);

    function UpdateTotalSupplyReceived(
        uint64 chain,
        CCHTTP_Types.update_supply_mssg memory params
    ) external returns (bool);

}