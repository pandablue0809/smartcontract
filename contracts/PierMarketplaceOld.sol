// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IWETH {
    function withdraw(uint256 amount) external;
}

contract PierMarketplaceOld is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct WTSListing {
        address tokenAddress;
        address seller;
        uint256 tokenAmountToSell;
        uint256 priceInWei;
        address paymentTokenAddress;
        bool isActive;
    }

    struct WTBListing {
        address tokenAddress;
        address buyer;
        uint256 tokenAmountToBuy;
        uint256 priceInWei;
        address paymentTokenAddress;
        bool isActive;
    }

    // Total number of listings
    uint256 public wtsListingCount = 0;
    uint256 public wtbListingCount = 0;

    address payable public pierStaking; // 50% fees go to staking contract
    address payable public pierWallet; // 50% fees go to wallet
    IERC20 public pierToken;
    IWETH public WETH; // WETH Contract

    //mapping of all listings
    mapping(uint256 => WTSListing) public wtsListings;
    mapping(uint256 => WTBListing) public wtbListings;

    // Blacklist mapping
    mapping(address => bool) private blacklist;

    modifier notBlacklisted() {
        require(!blacklist[msg.sender], "Address is blacklisted");
        _;
    }

    //Events
    event TokenListed(uint256 indexed listingId, address indexed seller, address indexed tokenAddress, uint256 tokenAmountToSell, uint256 priceInWei);
    event TokenToBuyListed(uint256 indexed listingId, address indexed buyer, address indexed tokenToBuyAddress, uint256 tokenAmountToBuy, uint256 priceInWei, address paymentTokenAddress);
    event TokenPurchased(uint256 indexed listingId, address indexed buyer, address indexed tokenAddress, uint256 tokenAmountToSell, uint256 priceInWei);
    event TokenSold(uint256 indexed listingId, address indexed seller, address indexed tokenAddress, uint256 tokenAmountToBuy, uint256 priceInWei);
    event WTSListingRemoved(uint256 indexed listingId, address indexed seller);
    event WTBListingRemoved(uint256 indexed listingId, address indexed buyer);

    //Errors
    error ApprovalFailed();
    error IncorrectAmountOfEtherSent(uint256 priceInWei);
    error SellerHasInsufficientBalance(uint256 balance);
    error TokenTransferFailed();
    error EtherTransferFailed();
    error OnlyTheSellerCanRemoveTheListing(address seller, address msgSender);
    error ListingDoesNotExist(uint256 listingId);
    error AmountMustBeGreaterThanZero(uint256 amount);
    error PriceMustBeGreaterThanZero(uint256 priceInWei);
    error TokenAddressMustBeValid(address tokenAddress);
    error PaymentTokenAddressMustBeValid(address paymentTokenAddress);
    error InsufficientAllowanceForPaymentToken(uint256 paymentTokenAllowance);
    error InsufficientBalance(uint256 buyerBalance);

    constructor(address _pierToken, address payable _pierStaking, address payable _pierWallet, address _wethAddress) Ownable(msg.sender) {
        pierToken = IERC20(_pierToken);
        pierStaking = _pierStaking;
        pierWallet = _pierWallet;
        WETH = IWETH(_wethAddress);
    }

    /* PUBLIC FUNCTIONS */

    function listTokenForSale(address tokenAddress, uint256 tokenAmountToSell, uint256 sellPriceInWei, address paymentTokenAddress) external notBlacklisted nonReentrant {
        if (tokenAmountToSell == 0) revert AmountMustBeGreaterThanZero(tokenAmountToSell);
        if (sellPriceInWei == 0) revert PriceMustBeGreaterThanZero(sellPriceInWei);
        if (tokenAddress == address(0)) revert TokenAddressMustBeValid(tokenAddress);

        uint256 allowance = IERC20(tokenAddress).allowance(msg.sender, address(this));
        require(allowance >= tokenAmountToSell, "Marketplace does not have enough allowance to transfer tokens");

        // Check if msg.sender has the amount of tokens to sell
        require(IERC20(tokenAddress).balanceOf(msg.sender) >= tokenAmountToSell, "Insufficient balance");

        // increase listing count
        wtsListingCount++;

        //Add listing to mapping
        wtsListings[wtsListingCount] = WTSListing(tokenAddress, msg.sender, tokenAmountToSell, sellPriceInWei, paymentTokenAddress, true);
        //Emit event
        emit TokenListed(wtsListingCount, msg.sender, tokenAddress, tokenAmountToSell, sellPriceInWei);
    }

    function listTokenToBuy(address tokenToBuyAddress, uint256 tokenAmountToBuy, uint256 buyPriceInWei, address paymentTokenAddress) external notBlacklisted nonReentrant {
        if (tokenAmountToBuy == 0) revert AmountMustBeGreaterThanZero(tokenAmountToBuy);
        if (buyPriceInWei == 0) revert PriceMustBeGreaterThanZero(buyPriceInWei);
        if (tokenToBuyAddress == address(0)) revert TokenAddressMustBeValid(tokenToBuyAddress);
        if (paymentTokenAddress == address(0)) revert PaymentTokenAddressMustBeValid(paymentTokenAddress);

        // Check if msg.sender has approved enough payment tokens to the marketplace
        uint256 paymentTokenAllowance = IERC20(paymentTokenAddress).allowance(msg.sender, address(this));
        require(paymentTokenAllowance >= buyPriceInWei, "Marketplace does not have enough allowance for payment tokens");

        // Check if msg.sender has enough balance of the payment token
        require(IERC20(paymentTokenAddress).balanceOf(msg.sender) >= buyPriceInWei, "Insufficient balance of payment token");

        // Increase buy listing count
        wtbListingCount++;

        // Add buy listing to mapping
        wtbListings[wtbListingCount] = WTBListing(tokenToBuyAddress, msg.sender, tokenAmountToBuy, buyPriceInWei, paymentTokenAddress, true);

        // Emit event
        emit TokenToBuyListed(wtbListingCount, msg.sender, tokenToBuyAddress, tokenAmountToBuy, buyPriceInWei, paymentTokenAddress);
    }

    function buyToken(uint256 listingId) external notBlacklisted nonReentrant {
        //Get listing from mapping
        WTSListing memory listing = wtsListings[listingId];
        //Check if listing exists
        if (listing.tokenAddress == address(0)) revert ListingDoesNotExist(listingId);

        //Check is listing is active
        if (!listing.isActive) revert ListingDoesNotExist(listingId);

        //Check if buyer has approved WETH to the marketplace
        uint256 allowance = IERC20(listing.paymentTokenAddress).allowance(msg.sender, address(this));
        if (allowance < listing.priceInWei) revert InsufficientAllowanceForPaymentToken(allowance);

        //Check if buyer has enough balance of WETH
        uint256 buyerBalance = IERC20(listing.paymentTokenAddress).balanceOf(msg.sender);
        if (buyerBalance < listing.priceInWei) revert InsufficientBalance(buyerBalance);

        // Check if the seller has enough tokens to sell.
        uint256 sellerBalance = IERC20(listing.tokenAddress).balanceOf(listing.seller);
        if (sellerBalance < listing.tokenAmountToSell) revert SellerHasInsufficientBalance(sellerBalance);

        //Set listing isActive=false
        wtsListings[listingId].isActive = false;

        // Transfer the tokens from the seller to the buyer.
        IERC20(listing.tokenAddress).safeTransferFrom(listing.seller, msg.sender, listing.tokenAmountToSell);

        // Calculate the fee. seller pays for the fee.
        (uint256 feeForStaking, uint256 feeForWallet) = _calculateFee(listing.priceInWei, listing.tokenAddress);

        // Transfer the total fee in WETH to this contract
        uint256 totalFee = feeForStaking + feeForWallet;
        IERC20(listing.paymentTokenAddress).safeTransferFrom(msg.sender, address(this), totalFee);

        _handleFeeDistribution(feeForStaking, feeForWallet);

        // Transfer the remaining amount to the seller
        uint256 amountToSeller = listing.priceInWei - feeForStaking - feeForWallet;

        IERC20(listing.paymentTokenAddress).safeTransferFrom(msg.sender, listing.seller, amountToSeller);

        // Emit the TokenPurchased event.
        emit TokenPurchased(listingId, msg.sender, listing.tokenAddress, listing.tokenAmountToSell, listing.priceInWei);
    }

    function sellToken(uint256 listingId) external notBlacklisted nonReentrant {
        //Get listing from mapping
        WTBListing memory listing = wtbListings[listingId];

        //Check if listing exists
        if (listing.tokenAddress == address(0)) revert ListingDoesNotExist(listingId);

        //Check is listing is active
        if (!listing.isActive) revert ListingDoesNotExist(listingId);

        //Check if buyer has approved WETH to the marketplace
        uint256 paymentTokenAllowance = IERC20(listing.paymentTokenAddress).allowance(listing.buyer, address(this));
        if (paymentTokenAllowance < listing.priceInWei) revert InsufficientAllowanceForPaymentToken(paymentTokenAllowance);

        //Check if buyer has enough balance of WETH
        uint256 buyerBalance = IERC20(listing.paymentTokenAddress).balanceOf(listing.buyer);
        if (buyerBalance < listing.priceInWei) revert InsufficientBalance(buyerBalance);

        // Check if the seller has enough tokens to sell.
        uint256 sellerBalance = IERC20(listing.tokenAddress).balanceOf(msg.sender);
        if (sellerBalance < listing.tokenAmountToBuy) revert SellerHasInsufficientBalance(sellerBalance);

        //Set listing isActive=false
        wtbListings[listingId].isActive = false;

        // Transfer the tokens from the seller to the buyer.
        IERC20(listing.tokenAddress).safeTransferFrom(msg.sender, listing.buyer, listing.tokenAmountToBuy);

        // Calculate the fee. seller pays for the fee.
        (uint256 feeForStaking, uint256 feeForWallet) = _calculateFee(listing.priceInWei, listing.tokenAddress);

        // Transfer the total fee in WETH to this contract
        uint256 totalFee = feeForStaking + feeForWallet;
        IERC20(listing.paymentTokenAddress).safeTransferFrom(listing.buyer, address(this), totalFee);

        _handleFeeDistribution(feeForStaking, feeForWallet);

        // Transfer the remaining amount from payment token to the seller
        uint256 amountToSeller = listing.priceInWei - feeForStaking - feeForWallet;

        IERC20(listing.paymentTokenAddress).safeTransferFrom(listing.buyer, msg.sender, amountToSeller);

        // Emit the TokenSold event.
        emit TokenSold(listingId, msg.sender, listing.tokenAddress, listing.tokenAmountToBuy, listing.priceInWei);
    }

    function removeWTSListing(uint256 listingId) external {
        // Get listing from mapping
        WTSListing memory listing = wtsListings[listingId];

        // Check if listing exists
        if (listing.tokenAddress == address(0)) revert ListingDoesNotExist(listingId);

        // Check if msg.sender is the seller
        if (msg.sender != listing.seller) revert OnlyTheSellerCanRemoveTheListing(listing.seller, msg.sender);

        //Set listing isActive=false
        wtsListings[listingId].isActive = false;

        // Emit event
        emit WTSListingRemoved(listingId, msg.sender);
    }

    function removeWTBListing(uint256 listingId) external {
        // Get listing from mapping
        WTBListing memory listing = wtbListings[listingId];

        // Check if listing exists
        if (listing.tokenAddress == address(0)) revert ListingDoesNotExist(listingId);

        // Check if msg.sender is the buyer
        if (msg.sender != listing.buyer) revert OnlyTheSellerCanRemoveTheListing(listing.buyer, msg.sender);

        //Set listing isActive=false
        wtbListings[listingId].isActive = false;

        // Emit event
        emit WTBListingRemoved(listingId, msg.sender);
    }

    /* RESTRICTED FUNCTIONS */


    //Allows the owner to set a new staking address
    function setPierStaking(address payable _pierStaking) external onlyOwner {
        pierStaking = _pierStaking;
    }

    //Allows the owner to set a new wallet address
    function setPierWallet(address payable _pierWallet) external onlyOwner {
        pierWallet = _pierWallet;
    }

    //Allows the owner to set a new pier token
    function setPierToken(address _pierToken) external onlyOwner {
        pierToken = IERC20(_pierToken);
    }

    //Add an address to the blacklist
    function addToBlacklist(address _address) external onlyOwner {
        blacklist[_address] = true;
    }

    //Remove an address from the blacklist
    function removeFromBlacklist(address _address) external onlyOwner {
        blacklist[_address] = false;
    }

    /* INTERNAL FUNCTIONS */

    function _calculateFee(uint256 amount, address tokenAddress) internal view returns (uint256, uint256) {
        // If the token being transacted is pierToken, return zero fees
        if (tokenAddress == address(pierToken)) {
            return (0, 0);
        }

        // 0.3% fee
        uint256 totalFee = amount * 3 / 1000;

        uint256 feeForStaking = totalFee / 2;
        uint256 feeForWallet = totalFee - feeForStaking;

        return (feeForStaking, feeForWallet);
    }

    function _handleFeeDistribution(uint256 feeForStaking, uint256 feeForWallet) internal {
        // Unwrap the total fee from WETH to ETH
        WETH.withdraw(feeForStaking + feeForWallet);

        // Send the specific fee portions to staking and wallet
        _sendETH(pierStaking, feeForStaking);
        _sendETH(pierWallet, feeForWallet);
    }

    function _sendETH(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Not enough ETH");

        (bool sent, ) = recipient.call{value: amount}("");
        require(sent, "Failed to send ETH");
    }

    // For receiving ETH from WETH
    receive() external payable {}
}
