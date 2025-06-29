//SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


import { ERC20Backed_hyperToken } from "./ERC20Backed_hyperToken.sol";
import { hyperLinkPool } from "./hyperLinkPool.sol";

contract hyperLINK is ERC20Backed_hyperToken {
    using SafeERC20 for IERC20;

    address public linkPool;

    constructor(address factory) ERC20Backed_hyperToken("hyperLINK", "hLINK", 18) {
        _setupRole(DEFAULT_ADMIN_ROLE, factory);
        _setupRole(POOL_ROLE, factory);
    }

    function init(
        uint64 _motherChainId,
        address _linkToken
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        super.init(
            _motherChainId, 
            "hyperLINK", // name
            "hLINK", // symbol
            18, // decimals
            _linkToken, //as backing token
            address(0), // pool will be set later
            address(0), // No wrapped native token needed for hyperLINK
            _linkToken, // link token itself for CrossChain transfers, won't be used
            address(this) // hyperLINK token itself
        );        
    }

    function setLinkPool(address _linkPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        linkPool = _linkPool;
        grantRole(POOL_ROLE, _linkPool);
    }

    function getLinkPool() external view returns (address) {
        return linkPool;
    }

    function wrapLink(uint256 amount) external {
        require(IERC20(linkToken).balanceOf(msg.sender) >= amount, "bal");
        require(IERC20(linkToken).allowance(msg.sender, address(this)) >= amount, "allw");
        
        IERC20(linkToken).safeTransferFrom(msg.sender, address(this), amount);

        IERC20(linkToken).safeApprove(linkPool, amount);
        hyperLinkPool(linkPool).depositLink(amount);
        IERC20(hyperLinkToken).safeTransfer(msg.sender, amount);
    }

    function unwrapLink(uint256 amount) external {
        IERC20(hyperLinkToken).safeTransferFrom(msg.sender, address(this), amount);

        IERC20(hyperLinkToken).safeApprove(linkPool, amount);
        hyperLinkPool(linkPool).withdrawLink(amount);
        IERC20(linkToken).safeTransfer(msg.sender, amount);
    }
}