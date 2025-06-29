//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import { ERC1967Proxy } from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { hyperLINK }  from "./hyperLINK.sol";
import { hyperLinkPool } from "./hyperLinkPool.sol";
import { MinimalBnMPool } from "./MinimalBnMPool.sol";

contract ProtocolFactory is Ownable {
    event Debug(string message);
    event DebugBytes(string message, bytes data);

    bytes cctcp_host_bytecode;
    bytes cchttp_peer_bytecode;
    bytes factory_bytecode;
    bytes manager_bytecode;


    address public erc20Backed_hyperTokenImpl;
    address public nativeBacked_hyperTokenImpl;
    address public erc721Backed_hyperTokenImpl;

    address public factory;
    
    constructor( address protocolDeployer ) Ownable() {
        transferOwnership(protocolDeployer);

        // Implementation contracts for hyper tokens
        // These contracts are used to deploy new hyper tokens
        // They are deployed once and then used to create proxies with CREATE2
        
    }

    modifier onlyFactory(){
        require(msg.sender == factory, "fctry");
        _;
    }


    function create2Contract(
        bytes memory bytecode,
        bytes32 salt
    ) internal returns (address addr) {
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
    }

    function loadERC20Backed_hyperTokenImpl(
        address impl
    ) external onlyOwner {
        erc20Backed_hyperTokenImpl = impl;
    }

    function loadNativeBacked_hyperTokenImpl(
        address impl
    ) external onlyOwner {
        nativeBacked_hyperTokenImpl = impl;
    }

    function loadERC721Backed_hyperTokenImpl(
        address impl
    ) external onlyOwner {
        erc721Backed_hyperTokenImpl = impl;
    }

    function loadCCTCPHostBytecode(
        bytes memory bytecode
    ) external onlyOwner {
        cctcp_host_bytecode = bytecode;
    }

    function loadCCHTTPPeerBytecode(
        bytes memory bytecode
    ) external onlyOwner {
        cchttp_peer_bytecode = bytecode;
    }

    function loadFactoryBytecode(
        bytes memory bytecode
    ) external onlyOwner {
        factory_bytecode = bytecode;
    }

    function loadManagerBytecode(
        bytes memory bytecode
    ) external onlyOwner {
        manager_bytecode = bytecode;
    }



    function estimatePoolAddress(
        address hyperToken,
        uint64 motherChain,
        uint8 decimals
    ) public view returns (address) {
        // Estimate the pool address based on the hyper token address, mother chain, and decimals
        bytes32 poolSalt = keccak256(abi.encodePacked(hyperToken, motherChain, decimals));
        
        bytes memory bytecode = abi.encodePacked(
            type(MinimalBnMPool).creationCode, 
            uint(uint160(hyperToken))
        );
        address poolAddress = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            poolSalt,
            //keccak256(type(BurnMintTokenPool).creationCode)
            keccak256(bytecode)
        )))));
        return poolAddress;
    }



    // Deterministic address calculation for the proxy
    function estimateTokenAddress(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) public view returns (address) {
        bytes32 salt = _hyperTokenSalt(_name, _symbol, _decimals);
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(erc20Backed_hyperTokenImpl, "")
        );
        bytes32 hash = keccak256(bytecode);
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            hash
        )))));
    }



    function estimateHyperERC721Address(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _backingToken,
        uint256 tokenId
    ) public view returns (address) {
        bytes32 salt = _hyperERC721Salt(_name, _symbol, _decimals, _backingToken, tokenId);
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(erc721Backed_hyperTokenImpl, "")
        );
        bytes32 hash = keccak256(bytecode);
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            hash
        )))));
    }



    // Helper to compute the salt
    function _hyperTokenSalt(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_name, _symbol, _decimals));
    }

    // Deploy the proxy using CREATE2 with deterministic address
    function createERC20Backed_hyperToken(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) external onlyFactory returns (address) {
        
        bytes32 salt = _hyperTokenSalt(_name, _symbol, _decimals);

        // Prepare empty init data (will call init after deployment)
        bytes memory initData = "";

        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(erc20Backed_hyperTokenImpl, initData)
        );

        address proxyAddr;
        assembly {
            proxyAddr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(proxyAddr) { revert(0, 0) }
        }

        return proxyAddr;
    }



    function _hyperERC721Salt(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _backingToken,
        uint256 tokenId
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_name, _symbol, _decimals, _backingToken, tokenId));
    }

    // Deploy the proxy using CREATE2 with deterministic address
    function createERC721Backed_hyperToken(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address backingToken,
        uint256 tokenId
    ) external onlyFactory returns (address) {
        
        bytes32 salt = _hyperERC721Salt(_name, _symbol, _decimals, backingToken, tokenId);

        // Prepare empty init data (will call init after deployment)
        bytes memory initData = "";

        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(erc721Backed_hyperTokenImpl, initData)
        );

        address proxyAddr;
        assembly {
            proxyAddr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(proxyAddr) { revert(0, 0) }
        }
        return proxyAddr;
    }



    function createNativeBacked_hyperToken(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) external onlyFactory returns (address) {
        
        bytes32 salt = _hyperTokenSalt(
            _name,
            _symbol,
            _decimals
        );

        // Prepare empty init data (will call init after deployment)
        bytes memory initData = "";

        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(nativeBacked_hyperTokenImpl, initData)
        );

        address proxyAddr;
        assembly {
            proxyAddr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(proxyAddr) { revert(0, 0) }
        }

        return proxyAddr;
    }


    function createHyperLINK() external onlyFactory returns (address) {
        
        bytes32 salt = keccak256(
            abi.encodePacked(
                "hyperLINK",
                "hLINK",
                uint8(18) // Assuming 18 decimals for LINK
            )
        );
        bytes memory byteCode = abi.encodePacked(
            type(hyperLINK).creationCode,
            uint(uint160(factory)) // Pass the factory address to the constructor
        );
        address hyperLinkAdd = create2Contract(
            byteCode,          
            salt
        );
        return hyperLinkAdd;
    }


    function createHyperLinkPool(
        address hyperLinkToken
    ) external onlyFactory returns (address ) {
        // Estimate the pool address based on the hyper token address and mother chain
        bytes32 poolSalt = keccak256(abi.encodePacked(hyperLinkToken));
        
        bytes memory bytecode = abi.encodePacked(
            type(hyperLinkPool).creationCode, 
            uint(uint160(hyperLinkToken))
        );
        
        address poolAddress = create2Contract(
            bytecode,
            poolSalt
        );
        
        return poolAddress;
    }



    function createMinimalBnMPool(
        address hyperToken,
        uint64 motherChain,
        uint8 decimals
    ) external onlyFactory returns (address) {
        // Estimate the pool address based on the hyper token address, mother chain, and decimals
        bytes32 poolSalt = keccak256(abi.encodePacked(hyperToken, motherChain, decimals));
        
        bytes memory bytecode = abi.encodePacked(
            type(MinimalBnMPool).creationCode, 
            uint(uint160(hyperToken)),
            uint(uint160(factory))
        );
        
        address poolAddress = create2Contract(
            bytecode,
            poolSalt
        );

        return poolAddress;
    }

    //
    //  Main protocols deployments
    //
    function deploy_CCTCP_Host(
        address protocolDeployer
    ) external onlyOwner returns (address) {
        bytes memory deployBytecode = abi.encodePacked(
            cctcp_host_bytecode,
            abi.encode(protocolDeployer)
        );
        bytes32 salt = keccak256(abi.encodePacked(protocolDeployer));
        address cctcp_host = create2Contract(deployBytecode, salt);

        return cctcp_host;
    }

    function deploy_CCHTTP_Peer(
    ) external onlyOwner returns (address) {
        bytes32 salt = keccak256(abi.encodePacked("Peer"));
        address cchttpPeer = create2Contract(
            cchttp_peer_bytecode,
            salt
        );

        return cchttpPeer;
    }

    function deployFactory(
        address protocolDeployer
    ) external onlyOwner returns (address) {
        bytes memory deployBytecode = abi.encodePacked(
            factory_bytecode,
            abi.encode(protocolDeployer)
        );
        bytes32 salt = keccak256(abi.encodePacked(protocolDeployer, "hTF"));
        factory = create2Contract(deployBytecode, salt);

        return factory;
    }

    function deployManager(
        address protocolDeployer
    ) external onlyOwner returns (address) {
        bytes memory deployBytecode = abi.encodePacked(
            manager_bytecode,
            abi.encode(protocolDeployer)
        );
        bytes32 salt = keccak256(abi.encodePacked(protocolDeployer, "hTM"));
        address manager = create2Contract(deployBytecode, salt);

        return manager;
    }

}