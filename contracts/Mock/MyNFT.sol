pragma solidity 0.7.3;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract MyNFT is ERC721 {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;

    constructor(string memory name_, string memory symbol_)
        public
        ERC721(name_, symbol_)
    {
        // nothing
    }

    function mint() external {
        uint256 current = _tokenIds.current();
        _safeMint(msg.sender, current);
        _tokenIds.increment();
    }

    function setTokenURI(uint256 tokenId, string memory _tokenURI) public {
        _setTokenURI(tokenId, _tokenURI);
    }
}
