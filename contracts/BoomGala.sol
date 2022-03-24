// contracts/BoomGala.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./ERC721A.sol";

contract BoomGala is ERC721A, Ownable, Pausable {
    using Address for address;

    // metadata URI
    string private _baseTokenURI;

    // partner address
    address private _partner = 0x9B645675E8D64759E5c36E30Dcb766d8CEC3d34F;

    // max partner allowed mint number
    uint private _maxPartnerAllowed = 100;

    struct SaleConfig {
        bool wlSaleStarted; // whitelist sale started?
        bool publicSaleStarted; // public sale started?
        uint wlPrice; // whitelist sale price
        uint wlMaxAmount; // whitelist sale max mint amount
        uint publicPrice; // public sale price
        uint publicMaxAmount; // public sale max mint amount
        uint reservedAmount; // reserve amount for marketing and give away purpose
    }

    SaleConfig public saleConfig;

    mapping(address => bool) public allowList; // whitelist

    constructor(
        uint256 maxBatchSize_,
        uint256 collectionSize_,
        string memory baseURI_) ERC721A("BoomGala","GALA", maxBatchSize_, collectionSize_)  {
        setupSaleConfig(false, false, 0.2 ether, 2, 0.4 ether, 3, 200);
        setBaseURI(baseURI_);
    }

    function tokensOfOwner(address _owner) external view returns(uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);
        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 index;
            for (index = 0; index < tokenCount; index++) {
                result[index] = tokenOfOwnerByIndex(_owner, index);
            }
            return result;
        }
    }

    function mintToPartner(uint256 quantity) public whenNotPaused payable  {
        SaleConfig memory config = saleConfig;

        bool _publicSaleStarted = config.publicSaleStarted;
        bool _wlSaleStarted = config.wlSaleStarted;

        // the whitelist sale must be started
        require (
            _publicSaleStarted == false && _wlSaleStarted == true,
            "Whitelist Sale is not started yet!"
        );

        require(
            quantity <= _maxPartnerAllowed, "Can only mint upto partner allowed amount each time"
        );

        // cant exceed wallet mint limits
        require(
            numberMinted(_partner) < _maxPartnerAllowed,
            "can not mint this many"
        );

        // cant exceed max supply
        require(totalSupply() + quantity <= collectionSize, "reached max supply");

        // the fund must be sufficient
        uint _wlPrice = config.wlPrice;
        require (
            msg.value >= _wlPrice * quantity,
            "Fund is not sufficient!"
        );

        _safeMint(_partner, quantity);
    }

    function wlSaleMint(uint256 quantity) public whenNotPaused payable  {
        SaleConfig memory config = saleConfig;

        bool _publicSaleStarted = config.publicSaleStarted;
        bool _wlSaleStarted = config.wlSaleStarted;

        // the public sale must be started
        require (
            _publicSaleStarted == false && _wlSaleStarted == true,
            "Whitelist Sale is not started yet!"
        );

        // Address must be whitelisted.
        require(allowList[msg.sender], "You are not whitelisted!");

        // cant exceed wl mint limits
        uint _wlMaxAmount = config.wlMaxAmount;
        require(
            quantity <= _wlMaxAmount,
            "can not mint this many"
        );

        // cant exceed wallet mint limits
        require(
            numberMinted(msg.sender) + quantity <= _wlMaxAmount,
            "can not mint this many"
        );

        // cant exceed max supply
        require(totalSupply() + quantity <= collectionSize, "reached max supply");

        // the fund must be sufficient
        uint _wlPrice = config.wlPrice;
        require (
            msg.value >= _wlPrice * quantity,
            "Fund is not sufficient!"
        );

        _safeMint(msg.sender, quantity);
    }

    function publicSaleMint(uint256 quantity) public whenNotPaused payable {
        SaleConfig memory config = saleConfig;

        bool _publicSaleStarted = config.publicSaleStarted;
        bool _wlSaleStarted = config.wlSaleStarted;

        // must not mint from contract
        require (
            msg.sender == tx.origin && !msg.sender.isContract(), "Are you bot?"
        );

        // the public sale must be started
        require (
            _publicSaleStarted == true && _wlSaleStarted == false,
            "Public Sale is not started yet!"
        );
        // cant exceed public mint limits
        uint _wlMaxAmount = config.wlMaxAmount;
        uint _publicMaxAmount = config.publicMaxAmount;
        require(
            quantity <= _publicMaxAmount,
            "can not mint this many"
        );
        // cant exceed wallet mint limits
        require(
            numberMinted(msg.sender) + quantity <= _wlMaxAmount + _publicMaxAmount,
            "can not mint this many"
        );
        // cant exceed max supply
        require(totalSupply() + quantity <= collectionSize, "reached max supply");

        // the fund must be sufficient
        uint _publicPrice = config.publicPrice;
        require (
            msg.value >= _publicPrice * quantity,
            "Fund is not sufficient!"
        );

        _safeMint(msg.sender, quantity);
    }

    function whitelist(address[] memory users) external onlyOwner {
        for(uint i = 0; i < users.length; i++) {
          allowList[users[i]] = true;
        }
    }

    function withdrawAll() external onlyOwner {
        require(payable(msg.sender).send(address(this).balance));
    }

    /**
     * Reserve some GALAs for marketing and giveaway purpose.
     */
    function reserveGiveaway(uint256 quantity) external onlyOwner {
        SaleConfig memory config = saleConfig;
        bool _publicSaleStarted = config.publicSaleStarted;
        bool _wlSaleStarted = config.wlSaleStarted;
        uint _reserved = config.reservedAmount;

        // the sale must not be started
        require (
            _publicSaleStarted == false && _wlSaleStarted == false,
            "The Reserve phase should only happen before the sale started!"
        );

        require(totalSupply() + quantity <= _reserved, "Exceeded giveaway supply");

        _safeMint(msg.sender, quantity);
    }

    function numberMinted(address owner) public view returns (uint256) {
        return _numberMinted(owner);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
    }

    function setupSaleConfig(bool _wlSaleStarted, bool _publicSaleStarted, uint _wlPrice,
    uint _wlMaxAmount, uint _publicPrice, uint _publicMaxAmount, uint _reservedAmount) internal onlyOwner {
        saleConfig = SaleConfig(
            _wlSaleStarted,
            _publicSaleStarted,
            _wlPrice,
            _wlMaxAmount,
            _publicPrice,
            _publicMaxAmount,
            _reservedAmount
        );
    }

    function setWlPrice(uint _newPrice) external onlyOwner {
        saleConfig.wlPrice = _newPrice;
    }

    function setWlMaxAmount(uint _newAmt) external onlyOwner {
        saleConfig.wlMaxAmount = _newAmt;
    }

    function setPublicPrice(uint _newPrice) external onlyOwner {
        saleConfig.publicPrice = _newPrice;
    }

    function setPublicMaxAmount(uint _newAmt) external onlyOwner {
        saleConfig.publicMaxAmount = _newAmt;
    }

    function setReservedAmount(uint _newAmount) external onlyOwner {
        saleConfig.reservedAmount = _newAmount;
    }

    function setPartnerAddr(address _partnerAddr) external onlyOwner {
        _partner = _partnerAddr;
    }

    function setMaxPartnerAllowed(uint _maxPartnerAllowed_) external onlyOwner {
        _maxPartnerAllowed = _maxPartnerAllowed_;
    }

    function startWLSale() external onlyOwner {
        saleConfig.wlSaleStarted = true;
        saleConfig.publicSaleStarted = false;
    }

    function startPublicSale() external onlyOwner {
        saleConfig.wlSaleStarted = false;
        saleConfig.publicSaleStarted = true;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
