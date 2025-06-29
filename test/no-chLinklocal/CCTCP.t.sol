//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";


import {CCTCP_Types} from "../../src/CCTCP_Types.sol";
import {CCTCP_Host} from "../../src/CCTCP_Host.sol";
import {ICCTCP_Host} from "../../src/interfaces/ICCTCP_Host.sol";
import {ICCTCP_Consumer} from "../../src/interfaces/ICCTCP_Consumer.sol";
import {HyperABICoder} from "../../src/libraries/HyperABICoder.sol";
import {PriceRetriever} from "../../src/PriceRetriever.sol";


contract mockLinkToken is ERC20, ERC20Burnable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}

contract mockWETH is ERC20, ERC20Burnable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function wrap() external payable {
        // Mock wrap function
        _mint(msg.sender, msg.value);
    }

    function unwrap(uint256 amount) external {
        // Mock unwrap function
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount); // Send ETH back to the user
    }

}

contract mockAggregatorV3Interface {
    int256 public latestAnswer;
    uint8 public decimals;

    constructor(int256 _latestAnswer, uint8 _decimals) {
        latestAnswer = _latestAnswer;
        decimals = _decimals;
    }

    function latestRoundData() external view returns (
        uint80,
        int256,
        uint256,
        uint256,
        uint80
    ) {
        return (0, latestAnswer, 0, 0, 0);
    }

}


contract mockRouterClient is IRouterClient {
    
    address public linkToken;
    address public wethToken;

      
    Client.EVM2AnyMessage public sentMessage;
    Client.Any2EVMMessage public receivedMessage;
    bool public isReceivedMessageSet = false;

    // Implement all functions from IRouterClient interface to make the contract concrete.
    function ccipSend(
        uint64 destinationChainSelector,
        Client.EVM2AnyMessage calldata message
    ) external payable override returns (bytes32) {
        return this._ccipSend(destinationChainSelector, message);
    }
/*
    function getSupportedTokens(
        uint64 destinationChainSelector
    ) external view override returns (address[] memory) {
        address[] memory tokens = new address[](2);
        tokens[0] = linkToken;
        tokens[1] = wethToken;
        return tokens;
    }
*/

    function getSentMessage() external view returns (Client.EVM2AnyMessage memory) {
        //sentMessage is storage
        //we need to copy it to memory to return
        //field by field so normal compiler can handle it
        Client.EVM2AnyMessage memory msgCopy = Client.EVM2AnyMessage({
            receiver: sentMessage.receiver,
            data: sentMessage.data,
            tokenAmounts: sentMessage.tokenAmounts,
            feeToken: sentMessage.feeToken,
            extraArgs: sentMessage.extraArgs
        });
        return msgCopy;
    }

    function setReceivedMessage(
        Client.Any2EVMMessage memory message
    ) external {
        //build tokenAmounts. It must be STORAGE you idiot
        
        
        // Mock setting a received message
        // Must copy field by field so any normal compiler can handle it
        receivedMessage.messageId = message.messageId;
        receivedMessage.sourceChainSelector = message.sourceChainSelector;
        receivedMessage.sender = message.sender;
        receivedMessage.data = message.data;
        
        for (uint256 i = 0; i < message.destTokenAmounts.length; i++) {
            receivedMessage.destTokenAmounts.push( Client.EVMTokenAmount({
                token: message.destTokenAmounts[i].token,
                amount: message.destTokenAmounts[i].amount
            }));
        }

        isReceivedMessageSet = true; // Set the flag to indicate a message has been received
    }

    function routeReceivedMessage(
        address cctcpHost
    ) external  returns (bool) {
        require(isReceivedMessageSet, "No message received to route");
        // Mock routing the received message

        CCTCP_Host(cctcpHost).ccipReceive( receivedMessage );

        console.log("Message routed successfully");
        return true; // Return true to indicate success
    }

    function _ccipSend(
        uint64 destChainId,
        Client.EVM2AnyMessage memory message
    ) external payable returns (bytes32) {
        // Mock sending a message
        sentMessage.feeToken = message.feeToken;
        sentMessage.data = message.data;
        sentMessage.receiver = message.receiver;
        sentMessage.extraArgs = message.extraArgs;
        console.log("Message sent to chain:", destChainId);
        return bytes32(0); // Return a mock message ID
    }
    
    function isChainSupported(
        //solhint-disable-next-line no-unused-vars
        uint64 destinationChainSelector
    ) external view returns (bool supported){
        // Mock check for chain support
        return true; // Assume all chains are supported for testing
    }

    function getFee(
        uint64 destinationChainSelector,
        Client.EVM2AnyMessage memory message
    ) external view returns (uint256 fee) {
        // Mock fee calculation
        return 0.1 ether; // Return a mock fee
    }
}

contract CCTCP_Test is Test, ICCTCP_Consumer {

    mockLinkToken public linkToken;
    mockWETH public wethToken;
    CCTCP_Host public cctcpHost;
    mockRouterClient public routerClient;
    uint64 public chainId;
    bool public delivered = false;

    address deployer;

    //for receiveMessage
    struct receivedMessage{
        uint64 origChainId;
        bytes origData;
    }
    receivedMessage public receivedMsg;

    function setUp() internal {
        // Initialize the mock router client
        routerClient = new mockRouterClient();
        
        // Initialize the LINK and WETH token (mock)
        linkToken = new mockLinkToken("Mock LINK", "mLINK");
        wethToken = new mockWETH("Mock WETH", "mWETH");
        // Mint some WETH tokens to the contract for testing
        
        // Initialize the CCTCP_Host contract
        cctcpHost = new CCTCP_Host(deployer);

        mockAggregatorV3Interface mock_nativeAggregator = new mockAggregatorV3Interface(2700 * 10**8, 18); // Mock price of 2700 USD for native token
        mockAggregatorV3Interface mock_linkAggregator = new mockAggregatorV3Interface(13 * 10**18, 18); // Mock price of 13 USD for LINK token

        cctcpHost.init(
            1, // Example chain ID
            address(routerClient), // Address of the mock router client
            address(linkToken), // Address of the mock LINK token
            address(this), // Address of the consumer contract
            address(0), // no hyperLink still
            address(wethToken), // Address of the mock WETH token
            address(mock_nativeAggregator), // Address of the mock native price aggregator
            address(mock_linkAggregator) // Address of the mock LINK price aggregator            
        );

        // Set the chain ID for testing
        chainId = 1; // Example chain ID
    }



    function testDeployment(
    ) public {
        deployer = vm.addr(1);
        vm.startPrank(deployer);

        setUp();

        vm.stopPrank();
        // Check if the CCTCP_Host contract is deployed correctly
        assertNotEq(address(cctcpHost), address(0), "CCTCP_Host contract should be deployed");

    }



    function testSendMessage() public {
        vm.startPrank(msg.sender);

        //mint some native ETH to the contract
        //vm.deal(msg.sender, 100 ether); // Mint 100 ETH to the contract
        
        //transfer from default sender top testContract
        vm.deal(msg.sender, 101 ether); // Mint 100 ETH to the test contract

        setUp();

        
        // Mint some LINK tokens to the contract for testing
        linkToken.mint(msg.sender, 1000 ether); // Mint 1000 LINK tokens

        // Approve the CCTCP_Host to spend LINK tokens
        linkToken.approve(address(cctcpHost), 100 ether); // Approve the CCTCP_Host to spend LINK tokens

        // Wrap the ETH to WETH
        wethToken.wrap{value: 100 ether}(); // Wrap the ETH to WETH

        wethToken.approve(address(cctcpHost), 10 ether); // Approve the CCTCP_Host to spend WETH

        // Test sending a message using CCTCP_Host
        // Send the message
        ICCTCP_Host.sendMessageParams memory params = ICCTCP_Host.sendMessageParams({
            destChain: 2, // Example destination chain ID
            origWallet: msg.sender,
            linkForAck: 100 ether, // Example LINK amount for acknowledgment
            linkToken: address(linkToken),
            data: bytes("Hello, CCTCP!"), // Example data to send
            feeToken: address(wethToken), // Example fee token
            feeAmount: 10 ether // Example fee amount
        });

        ERC20(wethToken).approve(address(cctcpHost), params.feeAmount);
        cctcpHost.sendMessage(params);

        Client.EVM2AnyMessage memory mssg = routerClient.getSentMessage();

        vm.stopPrank();
        // Check if the message was sent successfully
        address receiver = abi.decode(mssg.receiver, (address));

        CCTCP_Types.CCTCP_Segment memory segment = HyperABICoder.decodeCCTCP_Segment(mssg.data);
        assertEq( uint8(segment.CCTCP_Seg_Type), uint8(CCTCP_Types.CCTCP_Segment_Type.Data), "Segment type should be Data");
        assertEq( segment.CCTCP_Seg_Id, 1, "Segment ID should be 0 for the first message");
        assertEq( segment.CCIP_ops_token, address(linkToken), "CCIP ops token should match LINK token");
        assertEq( segment.CCIP_ops_amount, 100 ether, "CCIP ops amount should match the sent LINK amount");
        assertEq( segment.data.length, 13, "Segment data length should match the sent data length");
        assertEq( string(segment.data), "Hello, CCTCP!", "Message data should match" );
        assertEq( receiver, address(cctcpHost), "Receiver should match CCTCP_Host contract");
        assertEq( mssg.feeToken, address(wethToken), "Fee token should match WETH token");

        console.log("Message sent successfully with data:", string(segment.data));
    }



    function testReceiveMessageNoACK() public {
        // Test receiving a message using CCTCP_Host
        vm.startPrank(msg.sender);
        setUp();

        CCTCP_Types.CCTCP_Segment memory segment = CCTCP_Types.CCTCP_Segment({
            CCTCP_Seg_Id: 1, // Example segment ID
            CCTCP_Seg_Type: CCTCP_Types.CCTCP_Segment_Type.Data, // Example segment type
            CCIP_ops_token: address(linkToken), // LINK token address
            CCIP_ops_amount: 0, //No ack in my first try
            data: bytes("Hello from another chain!") // Example data to receive
        });
        bytes memory encodedSegment = HyperABICoder.encodeCCTCP_Segment(segment);
        // Create a mock Any2EVMMessage to simulate a received message
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(0), // Mock message ID
            sourceChainSelector: 2, // Example source chain ID
            sender: abi.encode(cctcpHost), // Sender address encoded
            data: encodedSegment, // Encoded segment data
            destTokenAmounts: new Client.EVMTokenAmount[](0) // No token amounts for this test
        });

        // Set the received message in the mock router client
        routerClient.setReceivedMessage(message);
        // Route the received message
        bool success = routerClient.routeReceivedMessage(address(cctcpHost));
        vm.stopPrank();
        // Check if the message was received successfully
        assertTrue(success, "Message should be received successfully");
        // Check if the receiveMessage function was called
        assertEq(receivedMsg.origChainId, 2, "Original chain ID should match the sent message");
        assertEq(string(receivedMsg.origData), "Hello from another chain!", "Original data should match the sent message");
        console.log("Message received successfully with data:", string(receivedMsg.origData));
    }

/*  Disabled: test it in forked environment

    function testReceiveMessageAndACK() public {
        // Test receiving a message using CCTCP_Host
        vm.startPrank(msg.sender);

        setUp();

        //mint some native LINK to the contract
        linkToken.mint(msg.sender, 1000 ether); // Mint 1000 LINK tokens
        // Approve the CCTCP_Host to spend LINK tokens
        linkToken.approve(address(cctcpHost), 100 ether); // Approve the CCTCP_Host to spend LINK tokens

        //fund cctcpHost with some LINK
        cctcpHost.fundPoolWithLink(address(linkToken), 100 ether); // Fund the CCTCP_Host with 100 LINK tokens

        CCTCP_Types.CCTCP_Segment memory segment = CCTCP_Types.CCTCP_Segment({
            CCTCP_Seg_Id: 1, // Example segment ID
            CCTCP_Seg_Type: CCTCP_Types.CCTCP_Segment_Type.Data, // Example segment type
            CCIP_ops_token: address(linkToken), // LINK token address
            CCIP_ops_amount: 0.01 ether, // ACK amount
            data: bytes("Hello from another chain!") // Example data to receive
        });
        bytes memory encodedSegment = HyperABICoder.encodeCCTCP_Segment(segment);
        // Create a mock Any2EVMMessage to simulate a received message
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(0), // Mock message ID
            sourceChainSelector: 2, // Example source chain ID
            sender: abi.encode(cctcpHost), // Sender address encoded
            data: encodedSegment, // Encoded segment data
            destTokenAmounts: new Client.EVMTokenAmount[](0) // No token amounts for this test
        });

        // Set the received message in the mock router client
        routerClient.setReceivedMessage(message);
        // Route the received message
        bool success = routerClient.routeReceivedMessage(address(cctcpHost));
        vm.stopPrank();
        // Check if the message was received successfully
        assertTrue(success, "Message should be received successfully");
        // Check if the receiveMessage function was called
        assertEq(receivedMsg.origChainId, 2, "Original chain ID should match the sent message");
        assertEq(receivedMsg.linkToken, address(linkToken), "Link token should match the sent message");
        assertEq(receivedMsg.linkAmount, 0.01 ether, "Link amount should be 0.01 ether for this message");
        assertEq(string(receivedMsg.origData), "Hello from another chain!", "Original data should match the sent message");
        console.log("Message received successfully with data:", string(receivedMsg.origData));


        //now lets check if ACK has been sent, it should be in the sentMessage
        Client.EVM2AnyMessage memory sentMessage = routerClient.getSentMessage();
        assertEq(sentMessage.receiver, abi.encode(cctcpHost), "Receiver should match CCTCP_Host contract");
        assertEq(sentMessage.tokenAmounts.length, 0, "ACK message should have no token amount");
        
        CCTCP_Types.CCTCP_Segment memory ackSegment = HyperABICoder.decodeCCTCP_Segment(sentMessage.data);
        assertEq( uint8(ackSegment.CCTCP_Seg_Type), uint8(CCTCP_Types.CCTCP_Segment_Type.Ack), "ACK Segment type should be ACK");
        assertEq( ackSegment.CCTCP_Seg_Id, 1, "ACK Segment ID should match the original segment ID");
        assertEq( ackSegment.CCIP_ops_token, address(linkToken), "ACK CCIP ops token should match LINK token");
        assertEq( ackSegment.CCIP_ops_amount, 0.01 ether, "ACK CCIP ops amount should match the sent LINK amount");
        console.log("ACK message sent successfully with amount:", ackSegment.CCIP_ops_amount, "and token:", ackSegment.CCIP_ops_token);
    }
*/

    function testProcessACK() public {
        // Test processing an ACK message
        vm.startPrank(msg.sender);

        setUp();

        //send the message so tcpHost has it and can recognize ACK
        //mint some native ETH to the contract
        vm.deal(msg.sender, 101 ether); // Mint 100 ETH to the test contract
        //wrap the ETH to WETH
        wethToken.wrap{value: 100 ether}(); // Wrap the ETH to WETH

        // Approve the CCTCP_Host to spend WETH tokens
        wethToken.approve(address(cctcpHost), 10 ether); // Approve the CCTCP_Host to spend WETH

        //mint some native LINK to the contract
        linkToken.mint(msg.sender, 100 ether); // Mint 100 LINK tokens
        //fund cctcpHost with some LINK
        linkToken.approve(address(cctcpHost), 10 ether); // Approve the CCTCP_Host to spend LINK tokens
        // Fund the CCTCP_Host with LINK tokens
        cctcpHost.fundPoolWithLink(address(linkToken), 10 ether); // Fund the CCTCP_Host with 100 LINK tokens
        // Send a message to the CCTCP_Host
        ICCTCP_Host.sendMessageParams memory params = ICCTCP_Host.sendMessageParams({
            destChain: 2, // Example destination chain ID
            origWallet: msg.sender,
            linkForAck: 0.01 ether, // Example LINK amount for acknowledgment
            linkToken: address(linkToken),
            data: bytes("Hello from another chain!"), // Example data to send
            feeToken: address(wethToken), // Example fee token
            feeAmount: 10 ether // Example fee amount
        });
        ERC20(wethToken).approve(address(cctcpHost), params.feeAmount);
        ERC20(linkToken).approve(address(cctcpHost), params.linkForAck);
        // Send the message
        cctcpHost.sendMessage(params);

        // Now we will simulate receiving an ACK message
        CCTCP_Types.CCTCP_Segment memory segment = CCTCP_Types.CCTCP_Segment({
            CCTCP_Seg_Id: 1, // Example segment ID
            CCTCP_Seg_Type: CCTCP_Types.CCTCP_Segment_Type.Ack, // ACK segment type
            CCIP_ops_token: address(linkToken), // LINK token address
            CCIP_ops_amount: 0.01 ether, // ACK amount
            data: bytes("ACK for Hello from another chain!") // Example data for ACK
        });
        bytes memory encodedSegment = HyperABICoder.encodeCCTCP_Segment(segment);
        // Create a mock Any2EVMMessage to simulate a received message
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(0), // Mock message ID
            sourceChainSelector: 2, // Example source chain ID
            sender: abi.encode(cctcpHost), // Sender address encoded
            data: encodedSegment, // Encoded segment data
            destTokenAmounts: new Client.EVMTokenAmount[](0) // No token amounts for this test
        });

        routerClient.setReceivedMessage(message);
        // Route the received message
        bool success = routerClient.routeReceivedMessage(address(cctcpHost));

        vm.stopPrank();
        assertTrue(success, "ACK message should be processed successfully");
    }

    function receiveMessage( //to be called from CCTCP Host
        uint64 origChainId,
        bytes memory origData
    ) external returns (bool) {
        console.log("Received message from chain:", origChainId);
        //copy to receivedMsg FIELD BY FIELD
        receivedMsg.origChainId = origChainId;
        receivedMsg.origData = origData;
        return true;
    }


    function notifyDeliver(
        uint64 origChainId,
        bytes memory origData
    ) external returns (bool){
        // Handle the delivery notification
        console.log("Delivery notification from chain:", origChainId);
        console.log("Original Data:", string(origData));
        return true;
    }


}