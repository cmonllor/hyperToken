//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract CCTCP_Types{
    
    enum CCTCP_Segment_Status{
        Untracked, // 0
        Sent, // 1
        Received, // 2
        Acknowledged, // 3
        ProcessedinDestination, // 4
        Retryed, // 5
        Failed // 6
    }

    enum CCTCP_Segment_Type{
        Data, // 0
        TkTx, // 1  Still not implemented
        Ack, // 2
        Rty // 3
    }

    //PDU
    struct CCTCP_Segment {
        uint24 CCTCP_Seg_Id;
        CCTCP_Segment_Type CCTCP_Seg_Type;
        address CCIP_ops_token; // Linktoken
        uint256 CCIP_ops_amount; // Link_for_ack when send/receive//retry, link refund when ack
        bytes data;
    } //403 bytes + data

    //IDU = PDU + ICI 
    struct CCTCP_Segment_Info {
        CCTCP_Segment_Status CCTCP_Seg_Status;
        CCTCP_Segment CCTCP_Seg;
        address origWallet; //for link refunds after ack
        uint256 total_CCTCP_Token_amount;
        uint256 first_update;
        uint256 last_update;
        uint8 retry_count;
    }

    //CCIP SDU
    //PDU administred by Chainlink wich we don't control
    struct CCIP_Package {
        bytes32 CCIP_Package_Id;
        uint64 origChain;
        address origHost;
        uint64 destChain;
        address destHost;
        CCTCP_Segment data;
    }
    
    //IDU, probably will not be used in this version
    //but let's stick to Mr Tannembaum's principles
    struct CCIP_Package_Status {
        bytes32 CCIP_Pkg_Id;
        uint256 timestamp;
        address feeToken;
        uint256 feeAmount;
        CCIP_Package CCIP_Package;
    }
}
