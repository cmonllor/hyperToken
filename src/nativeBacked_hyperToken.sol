// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {WETH9} from "@chainlink/contracts/src/v0.8/vendor/canonical-weth/WETH9.sol";

import {ERC20Backed_hyperToken} from "./ERC20Backed_hyperToken.sol";
import {IHyperTokenFactory} from "./interfaces/IHyperTokenFactory.sol";
import {FeesManager} from "./FeesManager.sol";

contract NativeBacked_hyperToken is ERC20Backed_hyperToken {
    using SafeERC20 for IERC20;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20Backed_hyperToken(name_, symbol_, decimals_) {}

    /*
    // Its the same signature as in ERC20Backed_hyperToken, so we can disable it
    // and use the one in ERC20Backed_hyperToken
    function init(
        uint64 _motherChainId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address _backingToken,
        address _pool,
        address _wrappedNative,
        address _linkToken,
        address _hyperLinkToken
    ) public override onlyRole(DEFAULT_ADMIN_ROLE) {
        super.init(
            _motherChainId,
            name,
            symbol,
            decimals, 
            _backingToken,
            _pool, 
            _wrappedNative, 
            _linkToken, 
            _hyperLinkToken
        );
    }
    */

    function wrapNative(
        uint256 amount
    ) external payable {
        require(motherChainId == 0, "Children doesn't HODL"); // xD
        //amount to wrap can be in native or in WETH
        if(amount == 0) {
            amount = msg.value;
            WETH9(wrappedNative).deposit{value: amount}();
        }
        else{
            require( IERC20(wrappedNative).allowance(msg.sender, address(this)) >= amount, "Not enough allowance for WETH");
            require( IERC20(wrappedNative).balanceOf(msg.sender) >= amount, "Not enough WETH balance");
            IERC20(wrappedNative).safeTransferFrom(msg.sender, address(this), amount);    
        }

        _mint(msg.sender, amount);
    }
}

