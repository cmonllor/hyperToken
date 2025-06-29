//SPDX-LicenseIdentifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract FeesManager {
    using SafeERC20 for IERC20;

    address public linkToken;
    address payable public wrappedNative;
    address public hyperLinkToken;
    
    function isValidFeeToken(address feeToken) public view returns (bool) {
        // Check if the fee token is valid
        return (feeToken == address(0) || feeToken == linkToken || feeToken == wrappedNative);
    }

    function isValidACKToken(address ackToken) public view returns (bool) {
        // Check if the ACK token is valid
        return (ackToken == hyperLinkToken || ackToken == linkToken);
    }

    function setHyperLink(
        address _hyperLinkToken
    ) external {
        // Only the owner can set the hyperLink token
        hyperLinkToken = _hyperLinkToken;
    }

    //TODO: compare if fee and ACK are the same token
    //TODO: validate fee and ACK amounts
    function cashInAndApproveFeesAndACK(
        address _feeToken,
        uint256 _feeAmount,
        address _ackToken,
        uint256 _ackAmount,
        address spender
    ) internal {
        if(_feeToken == address(0)) {
            require(msg.value == _feeAmount, "Invalid fee amount");
        } else{
            if( _feeToken != _ackToken ){
                // Transfer the fee amount from the sender to the contract
                require(isValidFeeToken(_feeToken), "Invalid fee token");
                require(IERC20(_feeToken).allowance(msg.sender, address(this)) >= _feeAmount, "Insufficient allowance");
                require(IERC20(_feeToken).balanceOf(msg.sender) >= _feeAmount, "Insufficient balance");
                if(_ackToken != address(0)) {
                    require(isValidACKToken(_ackToken), "Invalid ACK token");
                    require(IERC20(_ackToken).allowance(msg.sender, address(this)) >= _ackAmount, "Insufficient ACK allowance");
                    require(IERC20(_ackToken).balanceOf(msg.sender) >= _ackAmount, "Insufficient ACK balance");
                
                    IERC20(_ackToken).safeTransferFrom(msg.sender, address(this), _ackAmount);
                    IERC20(_ackToken).approve(spender, _ackAmount);
                }
                // Transfer the fee amount from the sender to the contract
                IERC20(_feeToken).safeTransferFrom(msg.sender, address(this), _feeAmount);
                IERC20(_feeToken).approve(spender, _feeAmount);
            } else{
                // If the fee token is the same as the ACK token, we transfer the sum of both amounts
                require(isValidFeeToken(_feeToken), "Invalid fee token");
                require(IERC20(_feeToken).allowance(msg.sender, address(this)) >= _feeAmount + _ackAmount, "Insufficient allowance");
                require(IERC20(_feeToken).balanceOf(msg.sender) >= _feeAmount + _ackAmount, "Insufficient balance");
                // Transfer the fee amount from the sender to the contract
                IERC20(_feeToken).safeTransferFrom(msg.sender, address(this), _feeAmount + _ackAmount);
                IERC20(_feeToken).approve(spender, _feeAmount + _ackAmount);
            }
        }
    }
}