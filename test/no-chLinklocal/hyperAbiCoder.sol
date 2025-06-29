//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CCTCP_Types} from "../../src/CCTCP_Types.sol";
import {CCHTTP_Types} from "../../src/CCHTTP_Types.sol";
import {HyperABICoder} from "../../src/libraries/HyperABICoder.sol";

contract HyperABICoderTest is Test{

    CCTCP_Types.CCTCP_Segment segment;
    CCHTTP_Types.CCHTTP_Message message;
    CCHTTP_Types.deploy_and_mint_mssg deployAndMintMessage;

    function tryEncodeCCTCP_Segment() public {

        segment = CCTCP_Types.CCTCP_Segment({
            CCTCP_Seg_Id: 1023, // Example segment ID
            CCTCP_Seg_Type: CCTCP_Types.CCTCP_Segment_Type.Ack,
            CCIP_ops_token: address(0x1234567890123456789012345678901234567890), // Example token address
            CCIP_ops_amount: (1<<252) - 1, // Example amount (max uint256)
            data: "test data for encoding"
        });
        bytes memory encodedData = HyperABICoder.encodeCCTCP_Segment(segment);
        console.logBytes(encodedData);

        uint headerLength = 3/* uint24 */ + 3/* uint24 */ + 20/* address */ + 32/* uint256 */;

        // Check the length of the encoded data
        assertEq(encodedData.length, headerLength + segment.data.length, "Encoded data length mismatch");
    }

    function tryDecodeCCTCP_Segment() public {
        bytes memory encodedData = HyperABICoder.encodeCCTCP_Segment(segment);
        CCTCP_Types.CCTCP_Segment memory decodedSegment = HyperABICoder.decodeCCTCP_Segment(encodedData);
        

        assertEq(uint24(decodedSegment.CCTCP_Seg_Type), uint24(segment.CCTCP_Seg_Type), "Segment Type mismatch");
        assertEq(decodedSegment.CCTCP_Seg_Id, segment.CCTCP_Seg_Id, "Segment Id mismatch");
        assertEq(decodedSegment.CCIP_ops_token, segment.CCIP_ops_token, "Token address mismatch");
        assertEq(decodedSegment.CCIP_ops_amount, segment.CCIP_ops_amount, "Amount mismatch");
        assertEq(decodedSegment.data, segment.data, "Data mismatch");
    }

    function tryEncodeCCHTTP_Message() public {
        message = CCHTTP_Types.CCHTTP_Message({
            operation: CCHTTP_Types.CCHTTP_Operation.DEPLOY_AND_MINT,
            data: "test data for CCHTTP encoding"
        });
        bytes memory encodedMessage = HyperABICoder.encodeCCHTTP_Message(message);
        console.logBytes(encodedMessage);
        uint headerLength = 3/* uint24 */;
        // Check the length of the encoded data
        assertEq(encodedMessage.length, headerLength + message.data.length, "Encoded CCHTTP message length mismatch");
    }

    function tryDecodeCCHTTP_Message() public {
        bytes memory encodedMessage = HyperABICoder.encodeCCHTTP_Message(message);
        CCHTTP_Types.CCHTTP_Message memory decodedMessage = HyperABICoder.decodeCCHTTP_Message(encodedMessage);

        assertEq(uint8(decodedMessage.operation), uint8(message.operation), "Operation mismatch");
        assertEq(decodedMessage.data, message.data, "Data mismatch");
    }

    function tryEncodeDeployAndMintMessage() public {
        deployAndMintMessage = CCHTTP_Types.deploy_and_mint_mssg({
            name_length: 4,
            name: "Test",
            symbol_length: 4,
            symbol: "TTST",
            decimals: 18,
            deployer: address(0x123),
            chainSupply: 500000,
            expectedTokenAddress: address(0x456),
            tokenType: CCHTTP_Types.HyperToken_Types.HyperERC20,
            backingToken: address(0x789),
            tokenId: (1<<128 -1)
        });
        bytes memory encodedMessage = HyperABICoder.encodeDeployAndMintMessage(deployAndMintMessage);
        console.logBytes(encodedMessage);

        uint headerLength = 1 /* namelength uint8 */ + 4 /* name */ + 1 /*symbollength*/+ 4 /* symbol */ + 1 /* decimals */ + 20 /* address */ + 32 /* uint256 */ + 20 /* address */ + 3 /* uint24 */ + 20 /* address */ + 32 /* uint256 */;
        // Check the length of the encoded data
        assertEq(encodedMessage.length, headerLength, "Encoded deploy and mint message length mismatch");
    }

    function tryDecodeDeployAndMintMessage() public {
        bytes memory encodedMessage = HyperABICoder.encodeDeployAndMintMessage(deployAndMintMessage);
        CCHTTP_Types.deploy_and_mint_mssg memory decodedMessage = HyperABICoder.decodeDeployAndMintMessage(encodedMessage);

        assertEq(decodedMessage.name_length, deployAndMintMessage.name_length, "Name length mismatch");
        assertEq(decodedMessage.name, deployAndMintMessage.name, "Name mismatch");
        assertEq(decodedMessage.symbol_length, deployAndMintMessage.symbol_length, "Symbol length mismatch");
        assertEq(decodedMessage.symbol, deployAndMintMessage.symbol, "Symbol mismatch");
        assertEq(decodedMessage.decimals, deployAndMintMessage.decimals, "Decimals mismatch");
        assertEq(decodedMessage.deployer, deployAndMintMessage.deployer, "Deployer mismatch");
        assertEq(decodedMessage.chainSupply, deployAndMintMessage.chainSupply, "Chain supply mismatch");
        assertEq(decodedMessage.expectedTokenAddress, deployAndMintMessage.expectedTokenAddress, "Expected token address mismatch");
        assertEq(uint8(decodedMessage.tokenType), uint8(deployAndMintMessage.tokenType), "Token type mismatch");
        assertEq(decodedMessage.backingToken, deployAndMintMessage.backingToken, "Backing token mismatch");
        assertEq(decodedMessage.tokenId, deployAndMintMessage.tokenId, "Token ID mismatch");
    }

    function tryEncodeUpdateSupplyMessage() public {
        CCHTTP_Types.update_supply_mssg memory updateSupplyMessage = CCHTTP_Types.update_supply_mssg({
            hyperToken: address(0x123),
            amount: -2000000,
            destination: address(0x456)
        });
        bytes memory encodedMessage = HyperABICoder.encodeUpdateSupplyMessage(updateSupplyMessage);
        console.logBytes(encodedMessage);

        uint headerLength = 20 /* address */ + 32 /* uint256 */ + 20 /* address */;
        // Check the length of the encoded data
        assertEq(encodedMessage.length, headerLength, "Encoded update supply message length mismatch");
    }

    function tryDecodeUpdateSupplyMessage() public {
        CCHTTP_Types.update_supply_mssg memory updateSupplyMessage = CCHTTP_Types.update_supply_mssg({
            hyperToken: address(0x123),
            amount: -2000000,
            destination: address(0x456)
        });
        bytes memory encodedMessage = HyperABICoder.encodeUpdateSupplyMessage(updateSupplyMessage);
        CCHTTP_Types.update_supply_mssg memory decodedMessage = HyperABICoder.decodeUpdateSupplyMessage(encodedMessage);

        assertEq(decodedMessage.hyperToken, updateSupplyMessage.hyperToken, "Hyper token mismatch");
        assertEq(decodedMessage.amount, updateSupplyMessage.amount, "New supply mismatch");
        //assertEq(decodedMessage.destination, updateSupplyMessage.destination, "Destination mismatch");
    }


    function testEncodeDecodeCCTCP_Segment() public {
        tryEncodeCCTCP_Segment();
        tryDecodeCCTCP_Segment();
    }

    function testEncodeDecodeCCHTTP_Message() public {
        tryEncodeCCHTTP_Message();
        tryDecodeCCHTTP_Message();
    }

    function testEncodeDecodeDeployAndMintMessage() public {
        tryEncodeDeployAndMintMessage();
        tryDecodeDeployAndMintMessage();
    }

    function testEncodeDecodeUpdateSupplyMessage() public {
        tryEncodeUpdateSupplyMessage();
        tryDecodeUpdateSupplyMessage();
    }
}