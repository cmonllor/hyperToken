//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {CCHTTP_Types} from "../CCHTTP_Types.sol";
import {CCTCP_Types} from "../CCTCP_Types.sol";

library HyperABICoder {
//as both CCTCP_Segment ans CCHTTP message use the ambiguous datatype bytes
//we cannot use abi.encode abi.decode
//we will have to use a custom encoder/decoder leveraging yul and assembly


    function encodeCCTCP_Segment(
        CCTCP_Types.CCTCP_Segment memory segment
    ) public pure returns (bytes memory){
        bytes memory data = abi.encodePacked(
            uint24(segment.CCTCP_Seg_Type),
            uint24(segment.CCTCP_Seg_Id),
            address(segment.CCIP_ops_token),
            uint256(segment.CCIP_ops_amount),
            segment.data
        );
        return data;
    }

    function decodeCCTCP_Segment(
        bytes memory data
    ) public pure returns (CCTCP_Types.CCTCP_Segment memory){
        CCTCP_Types.CCTCP_Segment memory segment;
        uint256 SegmentLength = data.length;
        
        bytes memory restOfSegment;

        bytes32 segmentTypeRead;
        assembly {
            segmentTypeRead :=  shr (  0xe8, mload( add(data,0x20) )  )
            restOfSegment := add ( data, 0x23 )
        }
        uint24 segmentType = uint24(uint256(segmentTypeRead));
        segment.CCTCP_Seg_Type = CCTCP_Types.CCTCP_Segment_Type(segmentType);

        bytes32 segmentIdRead;
        assembly {
            segmentIdRead :=  shr (  0xe8, mload( restOfSegment )  )
            restOfSegment := add ( restOfSegment, 0x03 )
        }
        segment.CCTCP_Seg_Id = uint24(uint256(segmentIdRead));
        
        bytes32 tokenRead;
        assembly {
            tokenRead := shr (  0x60, mload( restOfSegment )  ) 
            restOfSegment := add ( restOfSegment, 0x14 )
        }
        segment.CCIP_ops_token = address(uint160(uint256(tokenRead)));

        bytes32 amountRead;
        assembly {
            amountRead:= mload ( restOfSegment )  
            restOfSegment:= add ( restOfSegment, 0x20 )
        }
        segment.CCIP_ops_amount= uint256(amountRead);

        uint256 restOfSegmentLength  =  SegmentLength - (0x3 + 0x03 + 0x14 + 0x20);   
        segment.data = new bytes(restOfSegmentLength);
                
        assembly {
            mstore(  add ( segment, 0xa0 ), restOfSegmentLength  )

            for { let i:= 0 } lt( i, restOfSegmentLength ) { i:= add(i, 0x1) } {
                mstore8(   add (  add ( segment, 0xc0 ), i  )  , shr (  248, mload( add(restOfSegment, i) )  )   )
            }   
        }
        return segment;
    }

    function encodeCCHTTP_Message(
        CCHTTP_Types.CCHTTP_Message memory message
    ) public pure returns (bytes memory) {
        bytes memory data = abi.encodePacked(
            uint24(message.operation),
            message.data
        );
        return data;
    }

    function decodeCCHTTP_Message(
        bytes memory data
    ) public pure returns (CCHTTP_Types.CCHTTP_Message memory) {
        CCHTTP_Types.CCHTTP_Message memory message;
        uint256 messageLength = data.length;

        bytes memory restOfMessage;

        uint24 operationRead;
        assembly {
            operationRead := shr(0xe8, mload(add(data, 0x20)))
            restOfMessage := add(data, 0x23)
        }
        message.operation = CCHTTP_Types.CCHTTP_Operation(operationRead);

        uint256 restOfMessageLength = messageLength - 3; // 1 byte for operation
        message.data = new bytes(restOfMessageLength);

        assembly {
            mstore(add(message, 0x40), restOfMessageLength)

            for { let i := 0 } lt(i, restOfMessageLength) { i := add(i, 0x1) } {
                mstore8(   add( add(message, 0x60), i ), shr(  248, mload( add(restOfMessage, i) ) )  )
            }
        }
        return message;
    }

    function encodeDeployAndMintMessage(
        CCHTTP_Types.deploy_and_mint_mssg memory message
    ) public pure returns (bytes memory) {
        bytes memory data = abi.encodePacked(
            uint8(message.name_length),
            string(message.name),
            uint8(message.symbol_length),
            string(message.symbol),
            uint8(message.decimals),
            address(message.deployer),
            uint256(message.chainSupply),
            address(message.expectedTokenAddress),
            uint24(message.tokenType),
            address(message.backingToken),
            uint256(message.tokenId)
        );
        return data;
    }


    function decodeDeployAndMintMessage(
        bytes memory data
    ) public pure returns (CCHTTP_Types.deploy_and_mint_mssg memory) {
        CCHTTP_Types.deploy_and_mint_mssg memory message;
        
        bytes memory restOfMessage;

        uint8 nameLengthRead;
        assembly {
            nameLengthRead := shr(248, mload(add(data, 0x20)))
            restOfMessage := add(data, 0x21)
        }
        message.name_length = nameLengthRead;

        string memory nameRead = new string(nameLengthRead);
        assembly {
            for { let i := 0 } lt(i, nameLengthRead) { i := add(i, 0x1) } {
                mstore8(add(add(nameRead, 0x20), i), shr(248, mload(add(restOfMessage, i))))
            }
            restOfMessage := add(restOfMessage, nameLengthRead)

        }
        message.name = nameRead;
        
        uint8 symbolLengthRead;
        assembly {
            symbolLengthRead := shr(248, mload(restOfMessage))
            restOfMessage := add(restOfMessage, 0x1)
        }
        message.symbol_length = symbolLengthRead;

        string memory symbolRead = new string(symbolLengthRead);
        assembly {
            for { let i := 0 } lt(i, symbolLengthRead) { i := add(i, 0x1) } {
                mstore8(add(add(symbolRead, 0x20), i), shr(248, mload(add(restOfMessage, i))))
            }
            restOfMessage := add(restOfMessage, symbolLengthRead)

        }
        message.symbol = symbolRead;
        
        uint8 decimalsRead;
        assembly {
            decimalsRead := shr(248, mload(restOfMessage))
            restOfMessage := add(restOfMessage, 0x1)
        }
        message.decimals = decimalsRead;

        address deployerRead;
        assembly {
            deployerRead := shr(96, mload(restOfMessage))
            restOfMessage := add(restOfMessage, 0x14)
        }
        message.deployer = deployerRead;

        uint256 chainSupplyRead;
        assembly {
            chainSupplyRead := mload(restOfMessage)
            restOfMessage := add(restOfMessage, 0x20)
        }
        message.chainSupply = chainSupplyRead;

        address expectedTokenAddressRead;
        assembly {
            expectedTokenAddressRead := shr(96, mload(restOfMessage))
            restOfMessage := add(restOfMessage, 0x14)
        }
        message.expectedTokenAddress = expectedTokenAddressRead;

        uint24 tokenTypeRead;
        assembly {
            tokenTypeRead := shr(0xe8, mload(restOfMessage))
            restOfMessage := add(restOfMessage, 0x3)
        }
        message.tokenType = CCHTTP_Types.HyperToken_Types(tokenTypeRead);

        address backingTokenRead;
        assembly {
            backingTokenRead := shr(96, mload(restOfMessage))
            restOfMessage := add(restOfMessage, 0x14)
        }
        message.backingToken = backingTokenRead;

        uint256 tokenIdRead;
        assembly {
            tokenIdRead := mload(restOfMessage)
        }
        message.tokenId = tokenIdRead;
        return message;
    }


    function encodeUpdateSupplyMessage(
        CCHTTP_Types.update_supply_mssg memory message
    ) public pure returns (bytes memory) {
        bytes memory data = abi.encodePacked(
            address(message.hyperToken),
            int256(message.amount),
            address(message.destination)
        );
        return data;
    }

    function decodeUpdateSupplyMessage(
        bytes memory data
    ) public pure returns (CCHTTP_Types.update_supply_mssg memory) {
        CCHTTP_Types.update_supply_mssg memory message;
        
        bytes memory restOfMessage;

        address hyperTokenRead;
        assembly {
            hyperTokenRead := shr(96, mload(add(data, 0x20)))
            restOfMessage := add(data, 0x34)
        }
        message.hyperToken = hyperTokenRead;

        int256 amountRead;
        assembly {
            amountRead := mload(restOfMessage)
            restOfMessage := add(restOfMessage, 0x20)
        }
        message.amount = int256(amountRead);

        address destinationRead;
        assembly {
            destinationRead := shr(96, mload(restOfMessage))
        }
        message.destination = destinationRead;

        return message;
    }
}