//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface ICCTCP_Consumer {
    //To be called from CCTCP Host
    function receiveMessage(
        uint64 origChainId,
        bytes memory origData
    ) external returns (bool); 


    function notifyDeliver(
        uint64 origChainId,
        bytes memory origData
    ) external returns (bool); 
}