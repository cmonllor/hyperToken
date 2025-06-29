// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IHyperLINK } from "./interfaces/IHyperLINK.sol";

contract hyperLinkPool {

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    address public linkToken;
    address public hyperLinkToken;

    constructor(address _hyperLinkToken) {
        hyperLinkToken = _hyperLinkToken;
    }

    function init(address _linkToken) external {
        require(linkToken == address(0), "Link token already set");
        linkToken = _linkToken;
    }

    function depositLink(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        IERC20(linkToken).transferFrom(msg.sender, address(this), amount);
        // Mint hyperLinkToken to the sender
        IHyperLINK(hyperLinkToken).mint(msg.sender, amount);
        emit Deposit(msg.sender, amount);
    }

    function withdrawLink(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        IERC20(linkToken).transfer(msg.sender, amount);
        // Burn hyperLinkToken from the sender
        IHyperLINK(hyperLinkToken).burn(msg.sender,amount);
        emit Withdraw(msg.sender, amount);
    }

    function getLinkBalance() external view returns (uint256) {
        return IERC20(linkToken).balanceOf(address(this));
    }
    function getHyperLinkBalance() external view returns (uint256) {
        return IERC20(hyperLinkToken).balanceOf(msg.sender);
    }
}