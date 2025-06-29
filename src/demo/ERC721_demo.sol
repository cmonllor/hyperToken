// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract ERC721Demo is ERC721 {
    using Strings for uint256;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        bytes memory rtrString = abi.encodePacked('{\n');

        rtrString = abi.encodePacked(rtrString, '\t"name":"', name(), '",\n');
        rtrString = abi.encodePacked(rtrString, '\t"symbol":"', symbol(), '",\n');
        rtrString = abi.encodePacked(rtrString, '\t"tokenId":', tokenId.toString(), ',\n');
        rtrString = abi.encodePacked(rtrString, '\t"owner":"', Strings.toHexString(uint160(ownerOf(tokenId)), 20), '"\n');
        rtrString = abi.encodePacked(rtrString, "}");
        return string(rtrString);
    }
}