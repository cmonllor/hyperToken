//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IHyperLinkPool {
    function init(address _linkToken) external;

    function depositLink(uint256 amount) external;

    function withdrawLink(uint256 amount) external; 

    function getLinkBalance() external view returns (uint256);

    function getHyperLinkBalance() external view returns (uint256);
}