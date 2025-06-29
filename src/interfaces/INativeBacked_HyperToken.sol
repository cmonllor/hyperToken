//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20Backed_HyperToken} from "./IERC20Backed_HyperToken.sol";

interface INativeBacked_HyperToken is IERC20Backed_HyperToken{
    function wrapNative(
        uint256 amount
    ) external payable;
}