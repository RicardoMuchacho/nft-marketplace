// SPDX-License-Identifier: MIT

pragma solidity >= 0.8.24;

import "../lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract Marketplace is Ownable, ReentrancyGuard {
    using Strings for uint256;

    uint256 public feeFraction = 500; //5%
    uint256 public collectedFees;

    struct Listing {
        address nftAddress;
        address seller;
        uint256 tokenId;
        uint256 price;
    }

    struct ListingKey {
        address nftAddress;
        uint256 tokenId;
    }

    ListingKey[] public activeListings;
    // Maps NFT address and tokenId to their index in activeListings array (index+1, 0 means not present)
    mapping(address => mapping(uint256 => uint256)) private listingIndex;

    // Nested mapping
    mapping(address nftAddress => mapping(uint256 tokenId => Listing)) public listings;

    event listed(address indexed seller, address indexed nftAddress, uint256 indexed tokenId, uint256 price);
    event unlisted(address indexed seller, address indexed nftAddress, uint256 indexed tokendId, uint256 price);
    event boughtNFT(
        address indexed seller, address indexed nftAddress, uint256 indexed tokendId, address buyer, uint256 price
    );
    event feesCollected(uint256 fees);

    constructor() Ownable(msg.sender) {}

    // List NFT
    function listNFT(address nftAddress_, uint256 tokenId_, uint256 price_) external nonReentrant {
        require(price_ > 0, "Price can't be 0");
        require(IERC721(nftAddress_).ownerOf(tokenId_) == msg.sender, "Only owner can list NFT");
        require(listings[nftAddress_][tokenId_].seller == address(0), "Already listed");

        Listing memory listing_ =
            Listing({nftAddress: nftAddress_, seller: msg.sender, tokenId: tokenId_, price: price_});

        listings[listing_.nftAddress][listing_.tokenId] = listing_;

        // Add to activeListings
        activeListings.push(ListingKey(nftAddress_, tokenId_));
        listingIndex[nftAddress_][tokenId_] = activeListings.length; // index+1

        emit listed(msg.sender, nftAddress_, tokenId_, price_);
    }

    // Unlist NFT
    function unlistNFT(address contract_, uint256 tokenId_) external nonReentrant {
        Listing memory currentListing = listings[contract_][tokenId_];

        require(msg.sender == currentListing.seller, "Only Seller can unlist");

        // Remove from activeListings
        uint256 idx = listingIndex[contract_][tokenId_];
        if (idx > 0) {
            uint256 arrIdx = idx - 1;
            uint256 lastIdx = activeListings.length - 1;
            if (arrIdx != lastIdx) {
                ListingKey memory lastKey = activeListings[lastIdx];
                activeListings[arrIdx] = lastKey;
                listingIndex[lastKey.nftAddress][lastKey.tokenId] = arrIdx + 1;
            }
            activeListings.pop();
            listingIndex[contract_][tokenId_] = 0;
        }

        delete listings[contract_][tokenId_];

        emit unlisted(currentListing.seller, currentListing.nftAddress, currentListing.tokenId, currentListing.price);
    }

    // Buy NFT
    function buyNFT(address nftAddress_, uint256 tokenId_) external payable nonReentrant returns (Listing memory) {
        Listing memory currentListing = listings[nftAddress_][tokenId_];

        require(currentListing.seller != address(0), "Not listed");
        require(msg.value == currentListing.price, "Incorrect ETH amount");

        uint256 fees = (currentListing.price * feeFraction) / 10000;
        uint256 sellerProceeds = currentListing.price - fees;

        // transferNFT
        IERC721(nftAddress_).safeTransferFrom(currentListing.seller, msg.sender, currentListing.tokenId);

        // distribute ETH to seller and apply fees
        collectedFees += fees;

        (bool success,) = currentListing.seller.call{value: sellerProceeds, gas: 50000}("");
        require(success, "Failed to send payment to seller");

        // Remove from activeListings
        uint256 idx = listingIndex[nftAddress_][tokenId_];
        if (idx > 0) {
            uint256 arrIdx = idx - 1;
            uint256 lastIdx = activeListings.length - 1;
            if (arrIdx != lastIdx) {
                ListingKey memory lastKey = activeListings[lastIdx];
                activeListings[arrIdx] = lastKey;
                listingIndex[lastKey.nftAddress][lastKey.tokenId] = arrIdx + 1;
            }
            activeListings.pop();
            listingIndex[nftAddress_][tokenId_] = 0;
        }

        delete listings[nftAddress_][tokenId_];

        emit boughtNFT(
            currentListing.seller, currentListing.nftAddress, currentListing.tokenId, msg.sender, currentListing.price
        );
        return currentListing;
    }

    function getActiveListings() external view returns (Listing[] memory) {
        require(activeListings.length > 0, "No Listings");
        Listing[] memory result = new Listing[](activeListings.length);
        for (uint256 i = 0; i < activeListings.length; i++) {
            ListingKey memory key = activeListings[i];
            result[i] = listings[key.nftAddress][key.tokenId];
        }
        return result;
    }

    function withdrawFees() external onlyOwner {
        uint256 currentFees = collectedFees;
        collectedFees = 0;
        (bool success,) = owner().call{value: currentFees}("");
        if (!success) revert();

        emit feesCollected(currentFees);
    }
}
