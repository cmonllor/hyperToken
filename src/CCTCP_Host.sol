//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

import {CCIPReceiver} from "./mods/CCIPReceiver.sol";

import {FeesManager} from "./FeesManager.sol";
import {HyperABICoder} from "./libraries/HyperABICoder.sol";
import {ICCTCP_Consumer} from "./interfaces/ICCTCP_Consumer.sol";
import {ICCTCP_Host} from "./interfaces/ICCTCP_Host.sol";
import {CCTCP_Types} from "./CCTCP_Types.sol";
import {PriceRetriever} from "./PriceRetriever.sol";
import {hyperLINK} from "./hyperLINK.sol";
import {hyperLinkPool} from "./hyperLinkPool.sol";

contract CCTCP_Host is FeesManager, ICCTCP_Host, CCIPReceiver, Ownable, CCTCP_Types {
    using SafeERC20 for IERC20;
    using Client for IRouterClient;

    event Debug(string message);
    event DebugBytes(bytes message);
    event NonRevertError(string message);

    event ACK_new_cost(  //for offchain tracking and update in msgChain
        uint64 ACKingChain,
        uint64 msgChain,
        uint256 newCost
    );

    //we use Chainlink selector, not common EVM selector
    uint64 public constant ETHEREUM_SEPOLIA_SELECTOR = 16015286601757825753;

    //CCIP
    uint64 public chainId;
    address public routerClient;
    PriceRetriever public nativePriceRetriever;
    PriceRetriever public linkPriceRetriever;

    //CCTCP
    mapping(uint64 chainId => mapping(uint24 id => CCTCP_Segment_Info)) public CCTCP_SentSegments;
    mapping(uint64 chainId => mapping(uint24 id => CCTCP_Segment_Info)) public CCTCP_ReceivedSegments;
    //mapping( uint64 chainId => address CCTCP_Host) public CCTCP_Hosts;

    mapping(uint64 chainId => uint24 id) public CCTCP_LastSentSegment;
    mapping(uint64 chainId => uint24 id) public CCTCP_LastReceivedSegment;
    mapping(uint64 chainId => uint24 id) public CCTCP_LastAckedSegment;

    mapping(uint64 chainId => uint24 id) public CCTCP_LastRetryedSegment;

    mapping(uint64 chainId => uint24 id) public CCTCP_LastFailedSegment;
    mapping(uint64 chainId => uint24 id) public CCTCP_LastProcessedSegment;

    mapping(uint64 chainId => uint256 cost) public ackFeePerChain;

    address public CCHTTP_Peer;

    mapping(uint64 chain => address tkAddInDest) public linkTokens; //I wish all tokens were hyperTokens :(


    modifier onlyCCTCP_Host(address _CCTCP_PairHost) {
        require((address(this) == _CCTCP_PairHost), "CCTCP_Host: Host not allowed");
        //EVM predictable address: all CCTCP hosts will have the same address in all EVM chains
        _;
    }

    /*copied from EVM2EVMOnRamp I got from etherscan
    struct DynamicConfig {
        address router; // ──────────────────────────╮ Router address
        uint16 maxNumberOfTokensPerMsg; //           │ Maximum number of distinct ERC20 token transferred per message
        uint32 destGasOverhead; //                   │ Gas charged on top of the gasLimit to cover destination chain costs
        uint16 destGasPerPayloadByte; //             │ Destination chain gas charged for passing each byte of `data` payload to receiver
        uint32 destDataAvailabilityOverheadGas; // ──╯ Extra data availability gas charged on top of the message, e.g. for OCR
        uint16 destGasPerDataAvailabilityByte; // ───╮ Amount of gas to charge per byte of message data that needs availability
        uint16 destDataAvailabilityMultiplierBps; // │ Multiplier for data availability gas, multiples of bps, or 0.0001
        address priceRegistry; //                    │ Price registry address
        uint32 maxDataBytes; //                      │ Maximum payload data size in bytes
        uint32 maxPerMsgGasLimit; // ────────────────╯ Maximum gas limit for messages targeting EVMs
        //                                           │
        // The following three properties are defaults, they can be overridden by setting the TokenTransferFeeConfig for a token
        uint16 defaultTokenFeeUSDCents; // ──────────╮ Default token fee charged per token transfer
        uint32 defaultTokenDestGasOverhead; //       │ Default gas charged to execute the token transfer on the destination chain
        bool enforceOutOfOrder; // ──────────────────╯ Whether to enforce the allowOutOfOrderExecution extraArg value to be true.
    }
    DynamicConfig public ackChainConfig;
    uint256 public constant MESSAGE_FIXED_BYTES = 32 * 15;
    uint256 public constant MESSAGE_FIXED_BYTES_PER_TOKEN = 32 * (4 + (3 + 2));
    */
    
    constructor(address protocolDeployer) CCIPReceiver() Ownable() {
        nativePriceRetriever = new PriceRetriever();
        linkPriceRetriever = new PriceRetriever();
        transferOwnership(protocolDeployer);
    }

    function init(
        uint64 _chainId,
        address _routerClient,
        address _ccipToken,
        address _CCHTTP_Peer,
        address _hyperLinkToken,
        address _nativeToken,
        address _nativePriceAggregator,
        address _linkPriceAggregator
    ) external onlyOwner {
        CCIPReceiver(this).init(_routerClient);
        routerClient = _routerClient;
        
        CCHTTP_Peer = _CCHTTP_Peer;
        hyperLinkToken = _hyperLinkToken;
        linkToken = _ccipToken;
        emit Debug("CCIP Token: ");
        emit DebugBytes(abi.encodePacked(_ccipToken));
        wrappedNative = payable(_nativeToken);

        chainId = _chainId;
        
        uint8 nativeDecimals = 18;//IERC20Metadata(_nativeToken).decimals();
        nativePriceRetriever.init(_nativePriceAggregator, nativeDecimals);

        uint8 linkDecimals = IERC20Metadata(_ccipToken).decimals();
        linkPriceRetriever.init(_linkPriceAggregator, linkDecimals);

        transferOwnership(msg.sender);
    }
    /*
    function setDynamicConfig(
        DynamicConfig memory _ackChainConfig
    ) external onlyOwner {
        //memory to storage, copy one by one    
        ackChainConfig.router = _ackChainConfig.router;
        ackChainConfig.maxNumberOfTokensPerMsg = _ackChainConfig.maxNumberOfTokensPerMsg;
        ackChainConfig.destGasOverhead = _ackChainConfig.destGasOverhead;
        ackChainConfig.destGasPerPayloadByte = _ackChainConfig.destGasPerPayloadByte;
        ackChainConfig.destDataAvailabilityOverheadGas = _ackChainConfig.destDataAvailabilityOverheadGas;
        ackChainConfig.destGasPerDataAvailabilityByte = _ackChainConfig.destGasPerDataAvailabilityByte;
        ackChainConfig.destDataAvailabilityMultiplierBps = _ackChainConfig.destDataAvailabilityMultiplierBps;
        ackChainConfig.priceRegistry = _ackChainConfig.priceRegistry;
        ackChainConfig.maxDataBytes = _ackChainConfig.maxDataBytes;
        ackChainConfig.maxPerMsgGasLimit = _ackChainConfig.maxPerMsgGasLimit;
        ackChainConfig.defaultTokenFeeUSDCents = _ackChainConfig.defaultTokenFeeUSDCents;
        ackChainConfig.defaultTokenDestGasOverhead = _ackChainConfig.defaultTokenDestGasOverhead;
        ackChainConfig.enforceOutOfOrder = _ackChainConfig.enforceOutOfOrder;
    }
    */

    /*
     * Just in testnet. In testnet LINK is not CCIP crosschain transferable
     * so CCTCP needs to pool some LINK tokens to pay for ACKs and refunds
     */
    function fundPoolWithLink(
        address _linkToken,
        uint256 _amount
    ) external onlyOwner {
        require(_linkToken == linkToken, "CCTCP_Host: Invalid token");
        require(IERC20(_linkToken).balanceOf(msg.sender) >= _amount, "CCTCP_Host: Insufficient balance");
        require(IERC20(_linkToken).allowance(msg.sender, address(this)) >= _amount, "CCTCP_Host: Insufficient allowance");
        require(_amount > 0, "CCTCP_Host: Amount must be greater than zero");
        IERC20(_linkToken).safeTransferFrom(msg.sender, address(this), _amount);
        emit Debug("CCTCP_Host: Funded pool with LINK");
        emit DebugBytes(abi.encodePacked(_linkToken));
        emit DebugBytes(abi.encodePacked(_amount));
    }

    function enableChain(
        uint64 _chainId,
        address _linkTokenAddress
    ) external onlyOwner {
        linkTokens[_chainId] = _linkTokenAddress;
        ackFeePerChain[_chainId] = 17e15; //default value
    }


    function setAckCost(
        uint64 _chainId, //chain which will send an ACK to this chain
        uint256 _ackFee
    ) public onlyOwner{
        ackFeePerChain[ _chainId ] = _ackFee; 
    }


    function _ccipReceive
    (
        Client.Any2EVMMessage memory message
    ) 
        internal 
        override 
        onlyRouter  
        onlyCCTCP_Host(
            abi.decode(message.sender, (address))
        ) 
    {
        uint256 gas = gasleft();
        emit Debug("Gas left: ");
        emit DebugBytes(abi.encodePacked(gas));
        uint64 origChain = message.sourceChainSelector;
        CCTCP_Segment memory _CCTCP_Segment = HyperABICoder.decodeCCTCP_Segment(message.data);
        emit Debug("CCTCP_Host: Received CCIP message");
        if ( _CCTCP_Segment.CCTCP_Seg_Type == CCTCP_Segment_Type.Data ) {
            emit Debug("CCTCP_Host: received Data Segment");
            processDataSegment(origChain, _CCTCP_Segment);
        } else if ( _CCTCP_Segment.CCTCP_Seg_Type == CCTCP_Segment_Type.Ack ) {
            emit Debug("CCTCP_Host: received Ack Segment");
            processAckSegment(origChain, _CCTCP_Segment);
        } else if ( _CCTCP_Segment.CCTCP_Seg_Type == CCTCP_Segment_Type.Rty ) {
            emit Debug("CCTCP_Host: received Retry Segment");
            processRetryedMessage(origChain,  _CCTCP_Segment);
        } else {
            emit NonRevertError("CCTCP_Host: Unknown CCTCP_Segment_Type");
        }       
    }


    function processDataSegment(
        uint64 origChain,
        CCTCP_Segment memory _CCTCP_Segment
    ) internal {
        uint24 segId = _CCTCP_Segment.CCTCP_Seg_Id;
        if(CCTCP_LastReceivedSegment[origChain] < segId ) {
            emit Debug("CCTCP: Data to CCHTTP");

            if(ICCTCP_Consumer(CCHTTP_Peer).receiveMessage(
                origChain,
                _CCTCP_Segment.data
            )){
                emit Debug("CCTCP_Host: Data Segment processed successfully");
                CCTCP_LastReceivedSegment[origChain] = segId;

                CCTCP_ReceivedSegments[origChain][segId].CCTCP_Seg_Status = CCTCP_Segment_Status.Received;
                CCTCP_ReceivedSegments[origChain][segId].CCTCP_Seg = _CCTCP_Segment;
                CCTCP_ReceivedSegments[origChain][segId].first_update = block.timestamp;
                CCTCP_ReceivedSegments[origChain][segId].last_update = block.timestamp;
                CCTCP_ReceivedSegments[origChain][segId].retry_count = 0;
                CCTCP_ReceivedSegments[origChain][segId].total_CCTCP_Token_amount = _CCTCP_Segment.CCIP_ops_amount;
                
                if ( _CCTCP_Segment.CCIP_ops_amount > 0 ) {
                    emit Debug("CCTCP: Trying ACK");
                    if ( sendAck(origChain, _CCTCP_Segment)  ) {
                    
                        CCTCP_ReceivedSegments[origChain][segId].CCTCP_Seg_Status = CCTCP_Segment_Status.Acknowledged;
                        CCTCP_ReceivedSegments[origChain][segId].last_update = block.timestamp;
                        
                        emit Debug("CCTCP: Ack");
                    }    
                    else{
                        emit NonRevertError("CCTCP: Ack no");
                    }
                }
                else{
                    emit Debug("CCTCP: No Ack");
                }
            }
            else{
                emit NonRevertError("CCTCP: Data no. ACK no");
            }
        } else {
            emit NonRevertError("CCTCP: Seg already");
        }
        emit Debug("CCTCP_Host: Finished processing Data Segment");
    }


    function processAckSegment(
        uint64 origChain,
        CCTCP_Segment memory _CCTCP_Segment
    ) internal {
        uint24 segId = _CCTCP_Segment.CCTCP_Seg_Id;
        if( (CCTCP_SentSegments[origChain][segId].CCTCP_Seg_Status == CCTCP_Segment_Status.Sent) 
            || (CCTCP_SentSegments[origChain][segId].CCTCP_Seg_Status == CCTCP_Segment_Status.Retryed)
        ){
            emit Debug("CCTCP_Host: Processing Ack Segment");
            ICCTCP_Consumer _cons = ICCTCP_Consumer(CCHTTP_Peer);
            
            try _cons.notifyDeliver(
                origChain, 
                _CCTCP_Segment.data
            ) returns (bool success) {
                if(success){
                    emit Debug("CCTCP: Ack processed");
                    //refund unspent CCIP_ops_amount to the original wallet
                    emit Debug("Stored_message LINK:");
                    emit DebugBytes(abi.encodePacked(CCTCP_SentSegments[origChain][segId].CCTCP_Seg.CCIP_ops_token));
                    emit Debug("Ack Segment LINK:");
                    emit DebugBytes(abi.encodePacked(_CCTCP_Segment.CCIP_ops_token));
                    require(
                        CCTCP_SentSegments[origChain][segId].CCTCP_Seg.CCIP_ops_token == _CCTCP_Segment.CCIP_ops_token,
                        "CCTCP_Host: Token mismatch"
                    );
                    address refundWallet = CCTCP_SentSegments[origChain][segId].origWallet;
                    IERC20(_CCTCP_Segment.CCIP_ops_token).safeTransfer(refundWallet, _CCTCP_Segment.CCIP_ops_amount);
                    emit Debug("CCTCP: Ack refund");

                    CCTCP_SentSegments[origChain][segId].CCTCP_Seg_Status = CCTCP_Segment_Status.ProcessedinDestination;
                    CCTCP_SentSegments[origChain][segId].last_update = block.timestamp;
                    CCTCP_SentSegments[origChain][segId].total_CCTCP_Token_amount += _CCTCP_Segment.CCIP_ops_amount;
                    CCTCP_LastAckedSegment[origChain] = segId;                    
                    //return true
                }
                else{
                    emit NonRevertError("CCTCP: Ack no");
                    //return false
                }
            } catch {
                emit NonRevertError("CCTCP: Ack no");
                //return false
            }
        } 
        else{
            emit NonRevertError("CCTCP: Ack non-sent");
        }
    }


    function processRetryedMessage(
        uint64 _chain,
        CCTCP_Segment memory _CCTCP_Segment
    ) internal {
        uint24 segId = _CCTCP_Segment.CCTCP_Seg_Id;

        if( CCTCP_LastReceivedSegment[_chain] <= segId ){
            if( CCTCP_ReceivedSegments[_chain][segId].CCTCP_Seg_Status == CCTCP_Segment_Status.Acknowledged ){ 
                emit NonRevertError("CCTCP: Acked already");
            }
            else if( CCTCP_ReceivedSegments[_chain][segId].CCTCP_Seg_Status == CCTCP_Segment_Status.Received ){
                emit Debug("CCTCP: Retry received");
                //try to send ACK                
                if ( sendAck(_chain, _CCTCP_Segment) ){
                    emit Debug("CCTCP: ACK sent successfully");
                    CCTCP_ReceivedSegments[_chain][segId].CCTCP_Seg_Status = CCTCP_Segment_Status.Acknowledged;
                    CCTCP_ReceivedSegments[_chain][segId].last_update = block.timestamp;
                    CCTCP_ReceivedSegments[_chain][segId].total_CCTCP_Token_amount += _CCTCP_Segment.CCIP_ops_amount;
                    CCTCP_LastProcessedSegment[_chain] = segId;
                } else {
                    emit NonRevertError("CCTCP: Failed to send ACK");
                }
            }
            else{
                emit NonRevertError("CCTCP: Retry non-acked");
            }
        }
        else{
            processDataSegment(_chain, _CCTCP_Segment);
        }
    }


    function sendAck(
        uint64 origChain,
        CCTCP_Segment memory _CCTCP_Segment
    ) internal returns (bool) {
        uint24 segId = _CCTCP_Segment.CCTCP_Seg_Id;

        require(_CCTCP_Segment.CCIP_ops_token == linkTokens[origChain] || _CCTCP_Segment.CCIP_ops_token == hyperLinkToken, "CCTCP_Host: Invalid tk");

        CCTCP_Segment memory _CCTCP_Segment_Ack = CCTCP_Segment(
            segId,
            CCTCP_Segment_Type.Ack,
            _CCTCP_Segment.CCIP_ops_token,
            _CCTCP_Segment.CCIP_ops_amount,
            _CCTCP_Segment.data
        );
        emit DebugBytes(abi.encodePacked(_CCTCP_Segment_Ack.CCIP_ops_token));

        address _ackToken = address(0);
        if ( _CCTCP_Segment.CCIP_ops_token == hyperLinkToken ) {
            hyperLinkPool pool =  hyperLinkPool(hyperLINK(hyperLinkToken).getLinkPool());
            IERC20(hyperLinkToken).approve(
                address(pool),
                _CCTCP_Segment.CCIP_ops_amount
            );
            pool.withdrawLink(
                _CCTCP_Segment.CCIP_ops_amount
            );
        }
        _ackToken = linkToken;
                 
        Client.EVMTokenAmount[] memory _CCIP_ops;
        _CCIP_ops = new Client.EVMTokenAmount[](0);
        bytes memory encodedData = HyperABICoder.encodeCCTCP_Segment(_CCTCP_Segment_Ack);

        Client.EVM2AnyMessage memory mssg = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)),
            data: encodedData,
            tokenAmounts: _CCIP_ops,
            extraArgs: Client._argsToBytes(  Client.EVMExtraArgsV1({ gasLimit:3000000 })  ),
            feeToken: _ackToken
        });

        uint256 fees = IRouterClient(routerClient).getFee(
            origChain,
            mssg
        );
        emit ACK_new_cost(
            chainId,
            origChain,
            fees
        );
        if ( _CCTCP_Segment.CCIP_ops_amount >= fees ) {
            if (  _CCTCP_Segment.CCIP_ops_token == hyperLinkToken  ){
                _CCIP_ops = new Client.EVMTokenAmount[](1);
                _CCIP_ops[0] = Client.EVMTokenAmount({
                    token: _CCTCP_Segment.CCIP_ops_token,
                    amount: _CCTCP_Segment.CCIP_ops_amount - fees
                });
                mssg.tokenAmounts = _CCIP_ops;
            }
            else{
                //in testnet Link token is not CCIP crosschain transsferable
                //so we'll use CCTCP_Segment_Ack.CCIP_ops_amount field to send the refund amount
                _CCIP_ops = new Client.EVMTokenAmount[](0);
                mssg.tokenAmounts = _CCIP_ops;
                _CCTCP_Segment_Ack.CCIP_ops_amount = _CCTCP_Segment.CCIP_ops_amount - fees;
                encodedData = HyperABICoder.encodeCCTCP_Segment(_CCTCP_Segment_Ack);
                mssg.data = encodedData;
                emit Debug("CCTCP_Host: ACK Segment data updated with refund amount");
                emit DebugBytes(encodedData);
                emit DebugBytes(abi.encodePacked(_CCTCP_Segment_Ack.CCIP_ops_token));
            }    
        }
        else{
            emit NonRevertError("CCTCP_Host: ACK Segment amount is less than fees");
            //we can't send ACK with no refund, so we just return false
            return false; //disabled for ACK fees messuring in local test forked environment
        }

        emit Debug("CCTCP_Host: Approving ACK cost");
        
        IERC20(_ackToken).approve(
            routerClient,
            fees
            //amount in original seg - refund (amount in AKC seg)
        );

        try IRouterClient(routerClient).ccipSend(
            origChain,
            mssg
        ) {
            emit Debug("CCTCP_Host: ACK sent successfully");
            CCTCP_SentSegments[origChain][segId].CCTCP_Seg_Status = CCTCP_Segment_Status.Acknowledged;
            CCTCP_SentSegments[origChain][segId].CCTCP_Seg = _CCTCP_Segment;
            CCTCP_SentSegments[origChain][segId].first_update = block.timestamp;
            CCTCP_SentSegments[origChain][segId].last_update = block.timestamp;
            CCTCP_SentSegments[origChain][segId].retry_count = 0;
            CCTCP_LastAckedSegment[origChain] = segId;

            return true;
        } catch {
            emit NonRevertError("CCTCP: Ack send failed");
            return false;
        }
    }


    function sendMessage(
        sendMessageParams memory params
    ) external override returns (bool) {
        require( 
            params.linkToken == linkToken || 
            params.linkToken == hyperLinkToken, 
            "CCTCP_Host: Invalid token" 
        );
        require( 
            params.feeToken == linkToken ||  
            params.feeToken == wrappedNative, 
            "CCTCP_Host: Invalid fee token" 
        );

        if(params.feeToken == hyperLinkToken){
            hyperLinkPool pool = hyperLinkPool(hyperLINK(hyperLinkToken).getLinkPool());
            pool.withdrawLink( params.feeAmount );
            params.feeToken = linkToken; //use link token for CCIP

        }

        uint24 segId = CCTCP_LastSentSegment[params.destChain] + 1;
        CCTCP_Segment_Type segType = CCTCP_Segment_Type.Data;
        CCTCP_Segment memory _CCTCP_Segment = CCTCP_Segment(
            segId,
            segType,
            params.linkToken,
            params.linkForAck,
            params.data
        );

        bytes memory encodedData = HyperABICoder.encodeCCTCP_Segment(_CCTCP_Segment);
        Client.EVMTokenAmount[] memory _CCIP_ops;

        if( params.linkForAck > 0 ){
            if( params.linkToken == hyperLinkToken ){
                _CCIP_ops = new Client.EVMTokenAmount[](1);
                _CCIP_ops[0] = Client.EVMTokenAmount({
                    token: params.linkToken,
                    amount: params.linkForAck
                });
            }
            else{
                _CCIP_ops = new Client.EVMTokenAmount[](0);
            }
        }
        else{
            _CCIP_ops = new Client.EVMTokenAmount[](0);
        }

        uint256 fees = IRouterClient(routerClient).getFee(
            params.destChain,
            Client.EVM2AnyMessage({
                receiver: abi.encode(address(this)),
                data: encodedData,
                tokenAmounts: _CCIP_ops,
                extraArgs: Client._argsToBytes(  Client.EVMExtraArgsV1({ gasLimit:3000000 })  ),
                feeToken: params.feeToken
            })
        );
        require( params.feeAmount >= fees, "CCTCP_Host: Insufficient fee" );

        cashInAndApproveFeesAndACK(
            params.feeToken,
            params.feeAmount,
            params.linkToken,
            params.linkForAck,
            routerClient
        );
    
        try IRouterClient(routerClient).ccipSend(
            params.destChain,
            Client.EVM2AnyMessage({
                receiver: abi.encode(address(this)),
                data: encodedData,
                tokenAmounts: _CCIP_ops,
                extraArgs: Client._argsToBytes(  Client.EVMExtraArgsV1({ gasLimit:3000000 })  ),
                feeToken: params.feeToken
            })
        ) {
            CCTCP_SentSegments[params.destChain][segId].CCTCP_Seg_Status = CCTCP_Segment_Status.Sent;
            CCTCP_SentSegments[params.destChain][segId].CCTCP_Seg = _CCTCP_Segment;
            CCTCP_SentSegments[params.destChain][segId].origWallet = params.origWallet;
            CCTCP_SentSegments[params.destChain][segId].first_update = block.timestamp;
            CCTCP_SentSegments[params.destChain][segId].last_update = block.timestamp;
            CCTCP_SentSegments[params.destChain][segId].retry_count = 0;
            CCTCP_LastSentSegment[params.destChain] = segId;

        } catch {
            emit NonRevertError("CCTCP: Send failed");
            return false;
        }

        return true;
    }

    function retryMessage(
        uint24 segId,
        retryLastMessageParams memory params
    ) external override returns (bool) {
        require( params.linkToken == linkToken || params.linkToken == hyperLinkToken, "CCTCP_Host: Invalid token" );
        require( params.feeToken == linkToken || params.feeToken == wrappedNative, "CCTCP_Host: Invalid fee token" );
        require( CCTCP_SentSegments[params.destChain][segId].CCTCP_Seg_Status == CCTCP_Segment_Status.Sent, "CCTCP_Host: Segment not sent" );
        CCTCP_Segment memory _CCTCP_Segment = CCTCP_Segment(
            segId,
            CCTCP_Segment_Type.Rty,
            params.linkToken,
            params.linkForAck,
            CCTCP_SentSegments[params.destChain][segId].CCTCP_Seg.data
        );
        bytes memory encodedData = HyperABICoder.encodeCCTCP_Segment(_CCTCP_Segment);
        Client.EVMTokenAmount[] memory _CCIP_ops;
        if( params.linkForAck > 0 ){
            if( params.linkToken == hyperLinkToken ){
                _CCIP_ops = new Client.EVMTokenAmount[](1);
                _CCIP_ops[0] = Client.EVMTokenAmount({
                    token: params.linkToken,
                    amount: params.linkForAck
                });
            }
            else{
                _CCIP_ops = new Client.EVMTokenAmount[](0);
            }
        }
        else{
            _CCIP_ops = new Client.EVMTokenAmount[](0);
        }

        (uint256 fees,) = getFeesForMessage(
            getFeesForMessageParams({
                destChain: params.destChain,
                linkToken: params.linkToken,
                data: encodedData,
                feeToken: params.feeToken
            })
        );

        require( params.feeAmount >= fees, "CCTCP_Host: Insufficient fee" );
        
        if ( params.feeToken == params.linkToken ) {
            IERC20(params.feeToken).safeTransferFrom(
                msg.sender,
                address(this),
                (params.feeAmount + params.linkForAck)
            );
            IERC20(params.feeToken).safeApprove(
                routerClient,
                params.feeAmount 
            );
        }
        else{
            IERC20(params.feeToken).safeTransferFrom(
                msg.sender,
                address(this),
                fees
            );
            IERC20(params.feeToken).safeApprove(
                routerClient,
                fees
            );
            IERC20(params.linkToken).safeTransferFrom(
                msg.sender,
                address(this),
                params.linkForAck
            );
            
            try IRouterClient(routerClient).ccipSend(
                params.destChain,
                Client.EVM2AnyMessage({
                    receiver: abi.encode(address(this)),
                    data: encodedData,
                    tokenAmounts: _CCIP_ops,
                    extraArgs: Client._argsToBytes(  Client.EVMExtraArgsV1({ gasLimit:3000000 })  ),
                    feeToken: params.feeToken
                })
            ) {
                CCTCP_SentSegments[params.destChain][segId].CCTCP_Seg_Status = CCTCP_Segment_Status.Retryed;
                CCTCP_SentSegments[params.destChain][segId].CCTCP_Seg = _CCTCP_Segment;
                CCTCP_SentSegments[params.destChain][segId].first_update = block.timestamp;
                CCTCP_SentSegments[params.destChain][segId].last_update = block.timestamp;
                CCTCP_SentSegments[params.destChain][segId].retry_count += 1;
                CCTCP_LastRetryedSegment[params.destChain] = segId;

            } catch {
                emit NonRevertError("CCTCP: Retry failed");
                return false;
            }
        }
        return true;
    }

    function getFeesForMessage(
        getFeesForMessageParams memory params
    ) public view override returns (uint256 feeAmount, uint256 linkForAck) {
        uint24 segId = CCTCP_LastSentSegment[params.destChain] + 1;

        uint256 ackFee;
        
        
        CCTCP_Segment memory _CCTCP_Segment = CCTCP_Segment(
            segId,
            CCTCP_Segment_Type.Data,
            params.linkToken,
            type(uint256).max, //we don't know the ACK fee in advance, so we use max value
            params.data
        );
        Client.EVMTokenAmount[] memory _CCIP_ops;
        
        if(params.linkToken != address(0)){
            //emit Debug("CCTCP_Host: Estimating ACK fee");
            ackFee = ackFeePerChain[ params.destChain ] * 120 / 100;
            /*
            getACK_fee(
                params.destChain,
                params.data.length,
                3000000,
                0
            );
            */
        }
        else{
            ackFee = 0;
        }


        if (ackFee  > 0 ){
            if ( params.linkToken == hyperLinkToken ) {
                //emit Debug("HyperLink detected, buildong EVMTokenAmount");
                _CCIP_ops = new Client.EVMTokenAmount[](1);
                _CCIP_ops[0] = Client.EVMTokenAmount({
                    token: params.linkToken,
                    amount: ackFee
                });
            }
            else{
                //emit Debug("Regular Link: no EVMTokenAmounts");
                _CCIP_ops = new Client.EVMTokenAmount[](0);
            }
        }
        else{
            _CCIP_ops = new Client.EVMTokenAmount[](0);
        }
        bytes memory encodedData = HyperABICoder.encodeCCTCP_Segment(_CCTCP_Segment);
        
        Client.EVM2AnyMessage memory mssg = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)),
            data: encodedData,
            tokenAmounts: _CCIP_ops,
            extraArgs: Client._argsToBytes(  Client.EVMExtraArgsV1({ gasLimit:3000000 })  ),
            feeToken: params.feeToken
        });

        uint256 fees = IRouterClient(routerClient).getFee(
            params.destChain,
            mssg
        );

        return (fees, ackFee);
    }   
    /*
    function getACK_fee(
        uint64 destChain,
        uint256 dataLength,
        uint256 gasLimit,
        uint24 numTokens
    ) internal returns (uint256) {
         A plan: calculate ACK fees 
        uint256 gasPrice = tx.gasprice;
        emit Debug("CCTCP_Host: ACK gas price in wei");
        emit DebugBytes(abi.encodePacked(gasPrice));

        // Calculate gasUsage using only fields available in DynamicConfig
        // DynamicConfig fields used:
        // - destGasOverhead
        // - destGasPerPayloadByte
        // - destDataAvailabilityOverheadGas
        // - destGasPerDataAvailabilityByte
        // - destDataAvailabilityMultiplierBps
        // - defaultTokenDestGasOverhead

        uint256 gasUsage = gasLimit
            + ackChainConfig.destGasOverhead
            + (dataLength * ackChainConfig.destGasPerPayloadByte)
            + (numTokens * ackChainConfig.defaultTokenDestGasOverhead)
            + (
                (
                    ackChainConfig.destDataAvailabilityOverheadGas
                  + (
                        dataLength 
                        + MESSAGE_FIXED_BYTES
                        + (MESSAGE_FIXED_BYTES_PER_TOKEN * numTokens)
                        + 90000// transferFeeConfigConfig.destGasOverhead * numTokens
                    )*ackChainConfig.destGasPerDataAvailabilityByte            
                ) 
                * ackChainConfig.destDataAvailabilityMultiplierBps
                / 10000
            );

        emit Debug("CCTCP_Host: ACK gas usage");
        emit DebugBytes(abi.encodePacked(gasUsage));
        

        uint256 feeInWei = gasPrice * gasUsage;
        emit Debug("CCTCP_Host: ACK fee in wei");
        emit DebugBytes(abi.encodePacked(feeInWei));

        uint256 nativePriceInWei = nativePriceRetriever.getPriceInWei(); // USD per native token (18 decimals)
        emit Debug("CCTCP_Host: ACK_receivng_chain native token price in wei");
        emit DebugBytes(abi.encodePacked(nativePriceInWei));

        uint256 LinkPriceInWei = linkPriceRetriever.getPriceInWei(); // USD per LINK (18 decimals)
        emit Debug("CCTCP_Host: LINK Price:");
        emit DebugBytes(abi.encodePacked(LinkPriceInWei));

        // 2. Convert USD fee to LINK (18 decimals)
        uint256 gasFeeInLink =( feeInWei * LinkPriceInWei ) / nativePriceInWei;
        emit Debug("CCTCP_Host: ACK blockchain fee in LINK");
        emit DebugBytes(abi.encodePacked(gasFeeInLink));
        // 3. Add multiplier for buffer
        gasFeeInLink = (gasFeeInLink * 120) / 100;


        uint256 blockchainFeeInLINK = gasFeeInLink;

        uint256 networkFeeUSDe18;
        if(chainId == ETHEREUM_SEPOLIA_SELECTOR){
            networkFeeUSDe18 = numTokens>0? 180e16: 45e16;//to:Ethereum 1.35 (tktx)+ 0.45(msg) USD in 18 decimals
        }
        else if(destChain == ETHEREUM_SEPOLIA_SELECTOR){
            networkFeeUSDe18 = numTokens>0?90e16: 45e16; // From Ethereum 0.45+0.45 USD in 18 decimals
        }
        else{
            networkFeeUSDe18 = numTokens>0? 315e15:9e16; // 0.225(Tktx) + 0.09(msg) USD in 18 decimals
        }
        uint256 networkFeeInLINK = (networkFeeUSDe18 * 1e18) / LinkPriceInWei;
        emit Debug("CCTCP_Host: ACK network fee in LINK");
        emit DebugBytes(abi.encodePacked(networkFeeInLINK));

        uint256 feeInLINK = gasFeeInLink + networkFeeInLINK;
        emit Debug("CCTCP_Host: ACK total fee in LINK");
        emit DebugBytes(abi.encodePacked(feeInLINK));

        return feeInLINK;
        
    }
    */    
}