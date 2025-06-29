//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface ICCTCP_Host{

    struct sendMessageParams {
        uint64 destChain;
        address origWallet;
        uint256 linkForAck;
        address linkToken;
        bytes data;
        address feeToken;
        uint256 feeAmount;
    }
    function sendMessage(
        sendMessageParams memory params
    ) external returns (bool);


    struct retryLastMessageParams{
        uint64 destChain;
        uint256 linkForAck;
        address linkToken;
        address feeToken;
        uint256 feeAmount;
    }
    function retryMessage(
        uint24 segId,
        retryLastMessageParams memory params
    ) external returns (bool);


    struct getFeesForMessageParams {
        uint64 destChain;
        address feeToken;
        address linkToken;
        bytes data;
    }
    function getFeesForMessage(
        getFeesForMessageParams memory params
    ) external view returns (uint256 feeAmount, uint256 linkForAck);
}