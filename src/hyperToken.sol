// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { AccessControl } from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/access/AccessControl.sol";
import { IERC20Metadata } from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20 } from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/ERC20.sol";


abstract contract HyperToken is  ERC20, AccessControl {
    uint8 private s_decimals;
    uint256 internal crossChainSupply;

    address internal factory;
    address internal hT_Factory;

    bytes32 public constant POOL_ROLE = keccak256("POOL_ROLE");
    uint64 public motherChainId;

    address private pool;

    string private s_name;
    string private s_symbol;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_)       
    {
        s_decimals = decimals_;
    }

    function decimals() public view override(ERC20) returns (uint8) {
        return s_decimals;
    }

    function name() public override(ERC20) view returns (string memory) {
        return s_name;
    }
    
    function symbol() public override(ERC20) view returns (string memory) {
        return s_symbol;
    }

    function init(
        uint64 _motherChainId,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address _hT_Factory
    ) public virtual {
        factory = msg.sender;
        hT_Factory = _hT_Factory;
        motherChainId = _motherChainId;

        s_name = name_;
        s_symbol = symbol_;
        s_decimals = decimals_;
        _grantRole(DEFAULT_ADMIN_ROLE, hT_Factory); // so it can deploy children
        _grantRole(POOL_ROLE, hT_Factory); // so it can mint/burn
    }

    function updateSupply(
        uint256 newSupply, 
        address from_to
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(motherChainId == 0, "Children don't HODL"); // xD
        
        uint256 currentSupply = crossChainSupply;
        if(newSupply > currentSupply) {
            uint256 amountToMint = newSupply - currentSupply;
            _mint(from_to, amountToMint);
            crossChainSupply += amountToMint;
        } else if(newSupply < currentSupply) {
            uint256 amountToBurn = currentSupply - newSupply;
            //burn already done in child chain
            crossChainSupply -= amountToBurn;
        }
    }


    function setPool(address _pool) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if(hasRole(POOL_ROLE, pool)) {
            _revokeRole(POOL_ROLE, pool); // revoke the role from the old pool if it exists
        }
        _grantRole(POOL_ROLE, _pool);
        pool = _pool;
    }

    function getPool() external view returns (address) {
        return pool;
    }

    function getCCIPAdmin() external view returns (address) {
        return factory;
    } 


    function mint(address to, uint256 amount) external onlyRole(POOL_ROLE){
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(POOL_ROLE){
        _burn(from, amount);
    }

    function burn(uint256 amount) external onlyRole(POOL_ROLE){
        _burn(msg.sender, amount);
    }

    function burnFrom(address from, uint256 amount) external onlyRole(POOL_ROLE){
        _burn(from, amount);
    }

    
}
