// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { HyperToken } from "./hyperToken.sol";
import { IHyperTokenFactory } from "./interfaces/IHyperTokenFactory.sol";
import { FeesManager } from "./FeesManager.sol";

contract ERC20Backed_hyperToken is HyperToken, FeesManager {
    using SafeERC20 for IERC20;

    //event Debug(string message);
    // The backing token for this hyperToken
    address public backingToken;

    constructor(
        string memory name_, 
        string memory symbol_,
        uint8 decimals_
    ) HyperToken(name_, symbol_, decimals_) 
    {
        
    }

    function init(
        uint64 _motherChainId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address _backingToken,
        address _pool,
        address _wrappedNative,
        address _linkToken,
        address _hyperLinkToken,
        address _factory
    ) public  {
        
        //emit Debug("ERC20Backed_hyperToken init called");
        //uint256 gas = gasleft();
        //emit DebugBytes("12Gas left: ", abi.encodePacked(gas));
        super.init(
            _motherChainId,
            name,
            symbol,
            decimals,
            _factory
        );
        //gas = gasleft();
        //emit DebugBytes("13Gas left: ", abi.encodePacked(gas));
        wrappedNative = payable(_wrappedNative);
        linkToken = _linkToken;
        hyperLinkToken = _hyperLinkToken;

        backingToken = _backingToken;
        //gas = gasleft();
        //emit DebugBytes("14Gas left: ", abi.encodePacked(gas));
        setPool(_pool);
    }


    function wrap(
        uint256 amount
    ) external { //no role, open, permissionless and decentralized
        require( motherChainId == 0, "Children doesn't HODL" ); // xD 
        IERC20(backingToken).safeTransferFrom(msg.sender, address(this), amount);
        int256 amountInt = int256(amount); //positive amount for mint
        crossChainSupply += amount; //update cross chain supply
        IHyperTokenFactory(factory).updateSupply(
            address(this),
            amountInt,
            msg.sender,
            address(0), //no fee token
            0 //no fee amount
        );
        //_mint(msg.sender, amount);
    }

    function unwrap(
        uint256 amount,
        address feeToken,
        uint256 feeAmount
    ) external  { //no role, open, permissionless and decentralized
        if (motherChainId != 0) {
            //child
            cashInAndApproveFeesAndACK(
                feeToken,
                feeAmount,
                address(0), //no link token
                0, //no link amount
                factory
            );
        }
        
        int256 amountInt = -(int256(amount)); //negative amount for burn
        // call factory to update supply
        // if its a child it will send an 
        // UpdateSupplyRequest to the mother chain
        IHyperTokenFactory(factory).updateSupply(
            address(this),
            amountInt,
            msg.sender,
            feeToken,
            feeAmount
        );
    }

    function releaseBacking(
        uint256 amount,
        address to
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(motherChainId == 0, "Mom");
        IERC20(backingToken).safeTransfer(to, amount);
    }
}

