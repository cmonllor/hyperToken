//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IHyperToken is IERC20, IERC20Metadata{
    function init(
        uint64 motherChain,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address factory
    ) external;

    function updateSupply(
        uint256 newSupply, 
        address from_to
    ) external;

    function getCrossChainSupply() external view returns (uint256);

    function setPool(address _pool) external;

    function getPool() external returns (address);

    function getCCIPAdmin() external view returns (address);

    function mint(
        address to,
        uint256 amount
    ) external;

    function burn(
        address from,
        uint256 amount
    ) external;
}