//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IProtocolFactory {
    // View functions
    function erc20Backed_hyperTokenImpl() external view returns (address);
    function nativeBacked_hyperTokenImpl() external view returns (address);
    function erc721Backed_hyperTokenImpl() external view returns (address);
    function factory() external view returns (address);

    function estimatePoolAddress(address hyperToken, uint64 motherChain, uint8 decimals) external view returns (address);
    function estimateTokenAddress(string memory _name, string memory _symbol, uint8 _decimals) external view returns (address);
    function estimateHyperERC721Address(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _backingToken,
        uint256 tokenId
    ) external view returns (address);

    // Deployment functions
    function createERC20Backed_hyperToken(string memory _name, string memory _symbol, uint8 _decimals) external returns (address);
    function createERC721Backed_hyperToken(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address backingToken,
        uint256 tokenId
    ) external returns (address);
    function createNativeBacked_hyperToken(string memory _name, string memory _symbol, uint8 _decimals) external returns (address);
    function createHyperLINK() external returns (address);
    function createHyperLinkPool(address hyperLinkToken) external returns (address);
    function createMinimalBnMPool(address hyperToken, uint64 motherChain, uint8 decimals) external returns (address);

    // Bytecode loading
    function loadCCTCPHostBytecode(bytes memory bytecode) external;
    function loadCCHTTPPeerBytecode(bytes memory bytecode) external;
    function loadFactoryBytecode(bytes memory bytecode) external;
    function loadManagerBytecode(bytes memory bytecode) external;

    // Protocol deployments
    function deploy_CCTCP_Host(address protocolDeployer) external returns (address);
    function deploy_CCHTTP_Peer() external returns (address);
    function deployFactory(address protocolDeployer) external returns (address);
    function deployManager(address protocolDeployer) external returns (address);
}