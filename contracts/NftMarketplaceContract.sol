/**
 * SPDX-License-Identifier: MIT
 * @author Accubits
 * @title NFTMarketPlace
 */
pragma solidity 0.8.19;

import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title NFT MarketPlace
 * NFT MarketPlace contract to handle NFT resales, both fixed price and auction
 */
contract NFTMarketPlace is
    AccessControlEnumerable,
    IERC721Receiver,
    ReentrancyGuard,
    IERC1155Receiver,
    EIP712
{
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    /**
     * @notice To store Fixed price sale details
     */
    struct Sale {
        uint256 tokenId;
        uint256 price;
        uint256 quantity;
        address erc20Token;
        address seller;
    }

    /**
     * @notice To store auction sale details
     */
    struct Auction {
        uint256 tokenId;
        uint256 basePrice;
        uint256 salePrice;
        address erc20Token;
        uint256 quantity;
        address auctioner;
        address currentBidder;
        uint256 bidAmount;
    }

    struct Fee {
        address receiver;
        uint256 percentageValue;
    }

    event NftListed(
        uint256 indexed tokenId,
        address indexed nftAddress,
        address indexed seller,
        uint256 price,
        address erc20Token,
        uint256 quantity
    );

    event NftSold(
        uint256 indexed tokenId,
        address indexed nftAddress,
        address indexed seller,
        uint256 price,
        address erc20Token,
        address buyer,
        uint256 quantity
    );

    event SaleCanceled(uint256 tokenId, address sellerOrAdmin);

    event AuctionCreated(
        uint256 indexed tokenId,
        address indexed nftAddress,
        address indexed auctioner,
        uint256 basePrice,
        uint256 salePrice,
        address erc20Token,
        uint256 quantity
    );

    event BidPlaced(
        uint256 indexed tokenId,
        address indexed tokenContract,
        address indexed auctioner,
        address bidder,
        address erc20Token,
        uint256 quantity,
        uint256 price
    );

    event AuctionSettled(
        uint256 indexed tokenId,
        address indexed tokenContract,
        address indexed auctioner,
        address heighestBidder,
        address erc20Token,
        uint256 quantity,
        uint256 heighestBid
    );

    event AuctionCancelled(
        uint256 indexed tokenId,
        address indexed tokenContract,
        address indexed auctioner,
        uint256 quantity,
        address erc20Token,
        uint256 heighestBid,
        address heighestBidder
    );

    event FundTransfer(Fee royalty, Fee sellerProfit, Fee platformFee);

    event FundReceived(address indexed from, uint256 amount);

    /// Define the admin role
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// Define sale type, based this it is determined to start a fixed price sale or auction
    uint256 private constant TYPE_SALE = 1;
    uint256 private constant TYPE_AUCTION = 2;

    mapping(address => mapping(uint256 => mapping(address => Sale)))
        private mapSale;
    mapping(address => mapping(uint256 => mapping(address => Auction)))
        private mapAuction;
    mapping(address => Fee) creatorRoyalties;

    Fee private platformFee;

    bytes4 private ERC721InterfaceId = 0x80ac58cd; // Interface Id of ERC721
    bytes4 private ERC1155InterfaceId = 0xd9b67a26; // Interface Id of ERC1155
    bytes4 private royaltyInterfaceId = 0x2a55205a; // interface Id of Royalty

    /**
    @notice For signature verification of Typed Data
  */
    bytes32 public constant FIXED_PRICE_TYPEHASH =
        keccak256(
            "FixedPrice(uint256 tokenId,uint256 price,uint256 quantity,address erc20Token,address seller,address nftAddress)"
        );
    bytes32 public constant AUCTION_TYPEHASH =
        keccak256(
            "Auction(uint256 tokenId,uint256 basePrice,uint256 salePrice,uint256 quantity,address erc20Token,address seller,address nftAddress)"
        );

    /**
     * @notice Constructor
     * Invokes EIP712 constructor with Domain - Used for signature verification
     * @param _platformFee Fee type. Fee percentage and Receiver address
     * @param _rootAdmin Root admin address
     */
    constructor(
        Fee memory _platformFee,
        address _rootAdmin
    ) EIP712("NFTMarketPlace", "0.0.1") {
        _setPlatformFee(_platformFee);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, _rootAdmin);
    }

    /**
     * @notice To set platform fee and fee receiver
     * @param _platformFee Fee and fee receiver details
     */
    function PlatformFee(Fee memory _platformFee) external onlyOwner {
        _setPlatformFee(_platformFee);
    }

    /**
     * @notice onlyOwner
     * Modifier to check admin rights.
     * contract owner and root admin have admin rights
     */
    modifier onlyOwner() {
        require(_isAdmin(), "Restricted to admin");
        _;
    }

    /**
     * @notice isAdmin
     * Function to check does the msg.sender has admin role.
     * @return bool
     */
    function _isAdmin() internal view returns (bool) {
        return (hasRole(ADMIN_ROLE, _msgSender()) ||
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()));
    }

    /**
     * @notice callerNotAContract
     * Modifier to check given address is a contract address or not.
     */
    modifier callerNotAContract() {
        require(msg.sender == tx.origin, "Caller cannot be a contract");
        _;
    }

    /**
     * @notice listNft
     * Function to validate metadata and add nfts for the sale
     * @param _tokenId NFT unique ID
     * @param _price Unit price
     * @param _quantity Total number of tokens in sale
     * @param _erc20Token ERC20 token address, which can be used to buy this NFT
     * @param _seller Seller address
     * @param _nftAddress ERC721 or ERC1155 address
     */
    function _listNft(
        uint256 _tokenId,
        uint256 _price,
        uint256 _quantity,
        address _erc20Token,
        address _seller,
        address _nftAddress
    ) internal {
        require(_price > 0, "Sell Nfts: Wont Accept Zero Price");
        require(_quantity > 0, "Sell Nfts: Wont Accept Zero Value");
        require(_seller != address(0), "Sell Nfts: Zero Address");
        require(
            _nftAddress != address(0),
            "Sell Nfts: Nft Address Can Not Be Zero"
        );
        require(
            _isNFT(_nftAddress),
            "Sell Nfts: Not confirming to an NFT contract"
        );

        _setSaleDetails(
            _tokenId,
            _price,
            _quantity,
            _erc20Token,
            _seller,
            _nftAddress
        );

        emit NftListed(
            _tokenId,
            _nftAddress,
            _seller,
            _price,
            _erc20Token,
            _quantity
        );
    }

    /**
     * @notice setSaleDetails
     * Function to add nfts on the sale
     * @param _tokenId NFT unique ID
     * @param _price Unit price
     * @param _quantity Total number of tokens in sale
     * @param _erc20Token ERC20 token address, which can be used to buy this NFT
     * @param _sellerAddress Seller address
     * @param _nftAddress ERC721 or ERC1155 address
     */
    function _setSaleDetails(
        uint256 _tokenId,
        uint256 _price,
        uint256 _quantity,
        address _erc20Token,
        address _sellerAddress,
        address _nftAddress
    ) internal {
        Sale storage NftForSale = mapSale[_nftAddress][_tokenId][
            _sellerAddress
        ];

        /// Giving the ability to increase the quantity if the item is already listed
        /// Otherwise create a new listing
        if (NftForSale.quantity > 0) {
            NftForSale.quantity += _quantity;
        } else {
            NftForSale.tokenId = _tokenId;
            NftForSale.price = _price;
            NftForSale.quantity = _quantity;
            NftForSale.erc20Token = _erc20Token;
            NftForSale.seller = _sellerAddress;
        }
    }

    /**
     * @notice getSale
     * Function to get details of fixed price sale details nfts using token id
     * @param _tokenId NFT unique ID
     * @param _nftAddress ERC721 or ERC1155 address
     * @param _sellerAddress Seller address
     * @return Sale sale details
     */
    function getSale(
        uint256 _tokenId,
        address _nftAddress,
        address _sellerAddress
    ) public view returns (Sale memory) {
        Sale storage NftForSale = mapSale[_nftAddress][_tokenId][
            _sellerAddress
        ];
        return (NftForSale);
    }

    /**
     * @notice buyNft
     * Function to buy nfts using native crypto currency or multiple erc20 tokens
     * @param _tokenId use to buy nfts on sell
     * @param _quantity Token Quantity
     * @param _nftAddress Take erc721 and erc1155 address
     * @param _sellerAddress Seller address
     * @param _saleType Auction or Fixed price
     * @param _signature Metadata signature signed by admin
     */
    function buyNft(
        uint256 _tokenId,
        uint256 _quantity,
        address _nftAddress,
        address _sellerAddress,
        uint256 _saleType,
        bytes calldata _signature
    ) public payable nonReentrant {
        require(msg.sender != address(0), "BuyNfts: Zero Address");
        require(_nftAddress != address(0), "BuyNfts: Zero Address");
        _verifySignature(
            _tokenId,
            _sellerAddress,
            _nftAddress,
            _saleType,
            _signature
        );

        if (_saleType == TYPE_SALE) {
            require(_quantity > 0, "BuyNfts: Zero Quantitiy");
            _NftSaleFixedPrice(
                _tokenId,
                _quantity,
                _nftAddress,
                _sellerAddress
            );
        } else if (_saleType == TYPE_AUCTION) {
            _NftAuctionInstantBuy(_tokenId, _nftAddress, _sellerAddress);
        } else {
            revert("Sale type is invalid");
        }
    }

    /**
     * @notice fiatPurchase
     * This function can only be called by the admin account
     * The fiat payment will be converted into to crypto via on-ramp and transferred to the contract for
     * administering the payment split and token transfer on-chain
     * IMPORTANT: It should only be called after the right amount of crypto/token should received in the contract
     * The transfer should be confirmed off chain before calling this function
     * @param _tokenId use to buy nfts on sell
     * @param _quantity Token Quantity
     * @param _nftAddress Take erc721 and erc1155 address
     * @param _sellerAddress Seller address
     * @param _buyer NFT receiver address
     * @param _saleType Auction or Fixed price
     * @param _signature Metadata signature signed by admin
     */
    function fiatPurchase(
        uint256 _tokenId,
        uint256 _quantity,
        address _nftAddress,
        address _sellerAddress,
        address _buyer,
        uint256 _saleType,
        bytes calldata _signature
    ) public payable onlyOwner nonReentrant {
        require(_nftAddress != address(0), "BuyNfts: Zero Address");
        _verifySignature(
            _tokenId,
            _sellerAddress,
            _nftAddress,
            _saleType,
            _signature
        );

        if (_saleType == TYPE_SALE) {
            require(_quantity > 0, "BuyNfts: Zero Quantitiy");
            _NftSaleFixedPriceFiat(
                _tokenId,
                _quantity,
                _nftAddress,
                _sellerAddress,
                _buyer
            );
        } else if (_saleType == TYPE_AUCTION) {
            _NftAuctionInstantBuyFiat(
                _tokenId,
                _nftAddress,
                _sellerAddress,
                _buyer
            );
        } else {
            revert("Sale type is invalid");
        }
    }

    /**
     * @notice cancelListing
     * Function to cancel the fixed price resale using token ID
     * @param _tokenId  Is the token ID
     * @param _nftAddress  NFT contract address
     * @param _sellerAddress  The address of the seller
     * @param _signature Metadata signature signed by admin
     */
    function cancelListing(
        uint256 _tokenId,
        address _nftAddress,
        address _sellerAddress,
        bytes calldata _signature
    ) public {
        Sale storage NftForSale = mapSale[_nftAddress][_tokenId][
            _sellerAddress
        ];
        require(
            msg.sender == NftForSale.seller || _isAdmin(),
            "Cancel Listing : Only Seller or admin can cancel the Listing"
        );
        require(NftForSale.quantity > 0, "Buy Nfts :No active sale");
        _verifySignature(
            _tokenId,
            _sellerAddress,
            _nftAddress,
            TYPE_SALE,
            _signature
        );

        ///for erc721
        if (IERC721(_nftAddress).supportsInterface(ERC721InterfaceId)) {
            IERC721(_nftAddress).transferFrom(
                address(this),
                NftForSale.seller,
                _tokenId
            );
        }
        ///for erc1155
        else if (IERC1155(_nftAddress).supportsInterface(ERC1155InterfaceId)) {
            IERC1155(_nftAddress).safeTransferFrom(
                address(this),
                NftForSale.seller,
                _tokenId,
                NftForSale.quantity,
                ""
            );
        }

        delete mapSale[_nftAddress][_tokenId][_sellerAddress];

        emit SaleCanceled(_tokenId, msg.sender);
    }

    /**
     * @notice createAuction
     * Function to start resale with auction
     * @param auctionDetails Auction details
     * @param _nftAddress NFT contract address
     */
    function _createAuction(
        Auction memory auctionDetails,
        address _nftAddress
    ) internal {
        require(
            auctionDetails.basePrice > 0,
            "CreateAuction : Not Accept Zero BasePrice"
        );
        require(auctionDetails.quantity != 0, "CreateAuction: Zero Quantity");
        require(
            auctionDetails.auctioner != address(0),
            "CreateAuction: Zero Address"
        );
        require(_nftAddress != address(0), "CreateAuction: Zero Address");
        require(
            _isNFT(_nftAddress),
            "CreateAuction: Not confirming to an NFT contract"
        );

        _setAuctionDetails(
            auctionDetails.tokenId,
            auctionDetails.basePrice,
            auctionDetails.salePrice,
            auctionDetails.quantity,
            auctionDetails.erc20Token,
            auctionDetails.auctioner,
            _nftAddress
        );

        emit AuctionCreated(
            auctionDetails.tokenId,
            _nftAddress,
            auctionDetails.auctioner,
            auctionDetails.basePrice,
            auctionDetails.salePrice,
            auctionDetails.erc20Token,
            auctionDetails.quantity
        );
    }

    /**
     * @notice setAuctionDetails
     * Function to set the auction details
     * @param _tokenId NFT unique ID
     * @param _basePrice Unit base price, lowest bid value
     * @param _salePrice Unit sale price, for instant buy
     * @param _quantity Total number of tokens in sale
     * @param _erc20Token ERC20 token address, which can be used to buy this NFT
     * @param _auctioner Seller address
     * @param _nftAddress ERC721 or ERC1155 address
     */
    function _setAuctionDetails(
        uint256 _tokenId,
        uint256 _basePrice,
        uint256 _salePrice,
        uint256 _quantity,
        address _erc20Token,
        address _auctioner,
        address _nftAddress
    ) internal {
        Auction storage NftOnAuction = mapAuction[_nftAddress][_tokenId][
            _auctioner
        ];
        NftOnAuction.tokenId = _tokenId;
        NftOnAuction.basePrice = _basePrice;
        NftOnAuction.salePrice = _salePrice;
        NftOnAuction.erc20Token = _erc20Token;
        NftOnAuction.quantity = _quantity;
        NftOnAuction.auctioner = _auctioner;
    }

    /**
     * @notice getAuction
     * Function to get auction details
     * @param _tokenId NFT unique ID
     * @param _nftAddress ERC721 or ERC1155 address
     * @param _auctioner Seller address
     * @return Auction Auction data
     */
    function getAuction(
        uint256 _tokenId,
        address _nftAddress,
        address _auctioner
    ) external view returns (Auction memory) {
        Auction storage nftOnAuction = mapAuction[_nftAddress][_tokenId][
            _auctioner
        ];
        return (nftOnAuction);
    }

    /**
     * @notice placeBid
     * Function to place the bid on the nfts using native cryptocurrency and multiple erc20 token
     * @param _tokenId NFT unique ID
     * @param _price bid price
     * @param _nftAddress ERC721 or ERC1155 address
     * @param _auctioner Seller address
     * @param _signature Metadata signature signed by admin during NFT creation on platform
     */
    function placeBid(
        uint256 _tokenId,
        uint256 _price,
        address _nftAddress,
        address _auctioner,
        bytes calldata _signature
    ) public payable nonReentrant callerNotAContract {
        Auction storage NftOnAuction = mapAuction[_nftAddress][_tokenId][
            _auctioner
        ];

        require(
            NftOnAuction.quantity > 0,
            "Place Bid: Bid for non existing auction"
        );
        require(!_isAdmin(), "PlceBid: Admin Can Not Place Bid");
        require(
            msg.sender != NftOnAuction.auctioner,
            "Place Bid : Seller not allowed to place bid"
        );
        require(
            _price >= NftOnAuction.basePrice,
            "Place Bid : Price Less Than the base price"
        );
        require(
            _price > NftOnAuction.bidAmount,
            "The price is less then the previous bid amount"
        );
        _verifySignature(
            _tokenId,
            _auctioner,
            _nftAddress,
            TYPE_AUCTION,
            _signature
        );

        if (NftOnAuction.erc20Token == address(0)) {
            require(
                msg.value == _price,
                "Amount received and price should be same"
            );
            require(
                msg.value > NftOnAuction.bidAmount,
                "Amount received should be grather than the current bid"
            );
            if (NftOnAuction.currentBidder != address(0)) {
                payable(NftOnAuction.currentBidder).transfer(
                    NftOnAuction.bidAmount
                );
            }
        } else {
            uint256 checkAllowance = IERC20(NftOnAuction.erc20Token).allowance(
                msg.sender,
                address(this)
            );
            require(
                checkAllowance >= _price,
                "Place Bid : Allowance is Less then Price"
            );
            IERC20(NftOnAuction.erc20Token).safeTransferFrom(
                msg.sender,
                address(this),
                _price
            );
            if (NftOnAuction.currentBidder != address(0)) {
                IERC20(NftOnAuction.erc20Token).safeTransfer(
                    NftOnAuction.currentBidder,
                    NftOnAuction.bidAmount
                );
            }
        }

        NftOnAuction.bidAmount = _price;
        NftOnAuction.currentBidder = msg.sender;

        emit BidPlaced(
            _tokenId,
            _nftAddress,
            _auctioner,
            msg.sender,
            NftOnAuction.erc20Token,
            NftOnAuction.quantity,
            _price
        );
    }

    /**
     * @notice settleAuction
     * Function to settle auction.
     * Must be called by admin or auctioneer
     * @param _tokenId NFT unique ID
     * @param _nftAddress ERC721 or ERC1155 address
     * @param _auctioner Seller address
     * @param _signature Metadata signature signed by admin during NFT creation on platform
     */
    function settleAuction(
        uint256 _tokenId,
        address _nftAddress,
        address _auctioner,
        bytes calldata _signature
    ) public {
        Auction storage NftOnAuction = mapAuction[_nftAddress][_tokenId][
            _auctioner
        ];

        require(
            msg.sender == NftOnAuction.auctioner || _isAdmin(),
            "Settle Auction : Only Seller or admin can settle the auction"
        );
        _verifySignature(
            _tokenId,
            _auctioner,
            _nftAddress,
            TYPE_AUCTION,
            _signature
        );

        if (NftOnAuction.currentBidder != address(0)) {
            if (IERC721(_nftAddress).supportsInterface(ERC721InterfaceId)) {
                IERC721(_nftAddress).transferFrom(
                    address(this),
                    NftOnAuction.currentBidder,
                    _tokenId
                );
            } else if (
                IERC1155(_nftAddress).supportsInterface(ERC1155InterfaceId)
            ) {
                IERC1155(_nftAddress).safeTransferFrom(
                    address(this),
                    NftOnAuction.currentBidder,
                    _tokenId,
                    NftOnAuction.quantity,
                    ""
                );
            }

            _payOut(
                _nftAddress,
                // NftOnAuction.tokenId,
                NftOnAuction.bidAmount,
                NftOnAuction.erc20Token,
                NftOnAuction.auctioner,
                false
            );
        } else {
            if (IERC721(_nftAddress).supportsInterface(ERC721InterfaceId)) {
                IERC721(_nftAddress).transferFrom(
                    address(this),
                    NftOnAuction.auctioner,
                    _tokenId
                );
            } else if (
                IERC1155(_nftAddress).supportsInterface(ERC1155InterfaceId)
            ) {
                IERC1155(_nftAddress).safeTransferFrom(
                    address(this),
                    NftOnAuction.auctioner,
                    _tokenId,
                    NftOnAuction.quantity,
                    ""
                );
            }
        }

        emit AuctionSettled(
            NftOnAuction.tokenId,
            _nftAddress,
            _auctioner,
            NftOnAuction.currentBidder,
            NftOnAuction.erc20Token,
            NftOnAuction.quantity,
            NftOnAuction.bidAmount
        );

        delete mapAuction[_nftAddress][_tokenId][_auctioner];
    }

    /**
     * @notice cancelAuction
     * Function to cancel the auction
     * Must be called by admin or auctioneer
     * @param _tokenId NFT unique ID
     * @param _nftAddress ERC721 or ERC1155 address
     * @param _auctioner Seller address
     * @param _signature Metadata signature signed by admin during NFT creation on platform
     */
    function cancelAuction(
        uint256 _tokenId,
        address _nftAddress,
        address _auctioner,
        bytes calldata _signature
    ) external {
        Auction storage NftOnAuction = mapAuction[_nftAddress][_tokenId][
            _auctioner
        ];
        require(
            _isAdmin() || msg.sender == NftOnAuction.auctioner,
            "Cancel Auction: Admin or Auctioner can cancel auction"
        );
        require(
            NftOnAuction.tokenId == _tokenId,
            "Cancel Auction: Token id is not on auction"
        );
        require(
            NftOnAuction.quantity > 0,
            "Cancel Auction: Token id is not on auction"
        );
        _verifySignature(
            _tokenId,
            _auctioner,
            _nftAddress,
            TYPE_AUCTION,
            _signature
        );

        /// Return bid if there is any
        if (NftOnAuction.currentBidder != address(0)) {
            if (NftOnAuction.erc20Token == address(0)) {
                payable(NftOnAuction.currentBidder).transfer(
                    NftOnAuction.bidAmount
                );
            } else {
                IERC20(NftOnAuction.erc20Token).safeTransfer(
                    NftOnAuction.currentBidder,
                    NftOnAuction.bidAmount
                );
            }
        }

        /// Transfer the escrowed tokens back to the seller
        if (IERC721(_nftAddress).supportsInterface(ERC721InterfaceId)) {
            IERC721(_nftAddress).transferFrom(
                address(this),
                NftOnAuction.auctioner,
                _tokenId
            );
        } else if (
            IERC1155(_nftAddress).supportsInterface(ERC1155InterfaceId)
        ) {
            IERC1155(_nftAddress).safeTransferFrom(
                address(this),
                NftOnAuction.auctioner,
                _tokenId,
                NftOnAuction.quantity,
                ""
            );
        }

        emit AuctionCancelled(
            _tokenId,
            _nftAddress,
            _auctioner,
            NftOnAuction.quantity,
            NftOnAuction.erc20Token,
            NftOnAuction.bidAmount,
            NftOnAuction.currentBidder
        );

        delete mapAuction[_nftAddress][_tokenId][_auctioner];
    }

    /**
     * @notice onERC721Received
     * Function to decode the sale and auction data.
     * Used to start the auction and sale
     * when hit the safetransferfrom function from Erc721 Contracts
     * @param from token sender address
     * @param tokenId nfts id
     * @param data bytes data from safetransfer from function
     */
    function onERC721Received(
        address from,
        address,
        uint256 tokenId,
        bytes memory data
    ) public virtual override returns (bytes4) {
        (
            uint256 price,
            uint256 basePrice,
            address erc20Token,
            uint256 saleType
        ) = abi.decode(data, (uint256, uint256, address, uint256));

        /// The transfer function call will always be triggered from the token contract
        address nftAddress = msg.sender;

        if (saleType == 1) {
            _listNft(tokenId, price, 1, erc20Token, from, nftAddress);
        } else if (saleType == 2) {
            _createAuction(
                Auction(
                    tokenId,
                    basePrice,
                    price,
                    erc20Token,
                    1,
                    from,
                    address(0),
                    0
                ),
                nftAddress
            );
        } else {
            require(
                saleType == TYPE_SALE || saleType == TYPE_AUCTION,
                "Invalid Type"
            );
        }
        return (this.onERC721Received.selector);
    }

    /**
     * @notice onERC1155Received
     * Function to decode the sale and auction data.
     * Used to start the auction and sale
     * when hit the safetransferfrom function from ERC1155 Contracts
     * @param from from
     * @param id id
     * @param value value
     * @param data data
     */
    function onERC1155Received(
        address,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4) {
        (
            uint256 price,
            uint256 basePrice,
            address erc20Token,
            uint256 saleType
        ) = abi.decode(data, (uint256, uint256, address, uint256));

        // The transfer function call will always be triggered from the token contract
        address nftAddress = msg.sender;

        if (saleType == 1) {
            _listNft(id, price, value, erc20Token, from, nftAddress);
        } else if (saleType == 2) {
            _createAuction(
                Auction(
                    id,
                    basePrice,
                    price,
                    erc20Token,
                    value,
                    from,
                    address(0),
                    0
                ),
                nftAddress
            );
        } else {
            revert("Sale Type Is Invalid");
        }

        return (this.onERC1155Received.selector);
    }

    /**
     * @notice onERC1155Received
     * Dosn't support batch listing at the moment
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) public pure returns (bytes4) {
        revert("NFTMarketplace: Dosn't support batch listing at the moment");
    }

    /**
     * @notice supportsInterface
     * Function to check if the given address is compactable.
     * @return bool
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlEnumerable, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @notice setPlatformFee
     * Internal function to set platform fee percentage.
     * @param _platformFee Fee percentage
     * Must be given as percentage * 100
     */
    function _setPlatformFee(Fee memory _platformFee) internal {
        require(
            _platformFee.percentageValue <= 5000,
            "Fee: max allowed perecentage is 50"
        );
        platformFee = _platformFee;
    }

    /**
     * @notice fundTransfer
     * Manage fund transfers on purchase of NFT
     * @param _price Total price
     * @param _royaltyValue Royalty value
     * @param _tokenErc20 ERC20 token address
     * @param _isDirectPurchase Instant buy or settle auction
     * @param _seller Seller address
     * @param _royaltyReceiver Royalty receiver address
     */
    function _fundTransfer(
        uint256 _price,
        uint256 _royaltyValue,
        address _tokenErc20,
        bool _isDirectPurchase,
        address _seller,
        address _royaltyReceiver
    ) internal {
        uint256 sellerProfit;
        uint256 platformProfit;
        uint256 royaltyAmount;

        if (platformFee.percentageValue > 0) {
            platformProfit = _price.mul(platformFee.percentageValue).div(10000);
        }
        if (_royaltyReceiver != address(0) && _royaltyValue > 0) {
            royaltyAmount = _price.mul(_royaltyValue).div(10000);
        }
        sellerProfit = _price.sub(platformProfit.add(royaltyAmount));

        if (_tokenErc20 == address(0)) {
            if (_royaltyReceiver != address(0) && royaltyAmount > 0) {
                (bool isRoyaltyTransferSuccess, ) = payable(_royaltyReceiver)
                    .call{value: royaltyAmount}("");
                require(
                    isRoyaltyTransferSuccess,
                    "Fund Transfer: Transfer to royalty receiver failed."
                );
            }
            if (platformFee.receiver != address(0) && platformProfit > 0) {
                (bool isPlatformFeeTransferSuccess, ) = payable(
                    platformFee.receiver
                ).call{value: platformProfit}("");
                require(
                    isPlatformFeeTransferSuccess,
                    "Fund Transfer: Transfer to platform fee receiver failed."
                );
            }
            (bool isSellerTransferSuccess, ) = payable(_seller).call{
                value: sellerProfit
            }("");
            require(
                isSellerTransferSuccess,
                "Fund Transfer: Transfer to seller failed."
            );
        } else {
            if (_isDirectPurchase) {
                if (_royaltyReceiver != address(0) && royaltyAmount > 0) {
                    IERC20(_tokenErc20).safeTransferFrom(
                        msg.sender,
                        _royaltyReceiver,
                        royaltyAmount
                    );
                }
                if (platformFee.receiver != address(0) && platformProfit > 0) {
                    IERC20(_tokenErc20).safeTransferFrom(
                        msg.sender,
                        platformFee.receiver,
                        platformProfit
                    );
                }
                IERC20(_tokenErc20).safeTransferFrom(
                    msg.sender,
                    _seller,
                    sellerProfit
                );
            } else {
                if (_royaltyReceiver != address(0) && royaltyAmount > 0) {
                    IERC20(_tokenErc20).safeTransfer(
                        _royaltyReceiver,
                        royaltyAmount
                    );
                }
                if (platformFee.receiver != address(0) && platformProfit > 0) {
                    IERC20(_tokenErc20).safeTransfer(
                        platformFee.receiver,
                        platformProfit
                    );
                }
                IERC20(_tokenErc20).safeTransfer(_seller, sellerProfit);
            }
        }
        emit FundTransfer(
            Fee(_royaltyReceiver, royaltyAmount),
            Fee(_seller, sellerProfit),
            Fee(platformFee.receiver, platformProfit)
        );
    }

    /**
     * @notice getRoyaltyInfo
     * This function will fetch the details of the associated
     * Royalty informaion of an NFT
     * @param _contract token contract address
     * @param _tokenId token ID
     * @param _amount total amount paymable
     * @return user Royalty receiver address
     * @return royaltyAmount Royalty value
     */
    function _getRoyaltyInfo(
        address _contract,
        uint256 _tokenId,
        uint256 _amount
    ) internal view returns (address user, uint256 royaltyAmount) {
        if (IERC2981(_contract).supportsInterface(royaltyInterfaceId)) {
            (user, royaltyAmount) = IERC2981(_contract).royaltyInfo(
                _tokenId,
                _amount
            );
        }
    }

    /**
     * @notice payOut
     * Function to manage various fund transfers
     * @param _nftAddress ERC721 or ERC1155 address
     * @param _totalAmount Total fund
     * @param _currency ERC20 token address
     * @param _seller Seller address
     * @param _isDirectPurchase Instant buy or settle auction
     */
    function _payOut(
        address _nftAddress,
        uint256 _totalAmount,
        address _currency,
        address _seller,
        bool _isDirectPurchase
    ) internal {
        address royaltyReceiver = creatorRoyalties[_nftAddress].receiver;
        uint256 royaltyValue = creatorRoyalties[_nftAddress].percentageValue;

        _fundTransfer(
            _totalAmount,
            royaltyValue,
            _currency,
            _isDirectPurchase,
            _seller,
            royaltyReceiver
        );
    }

    /**
     * @notice NftSaleFixedPrice
     * Function to handle fixed price sale with direct payment
     * @param _tokenId use to buy nfts on sell
     * @param _quantity Token Quantity
     * @param _nftAddress ERC721 or ERC1155 address
     * @param _sellerAddress Seller address
     */
    function _NftSaleFixedPrice(
        uint256 _tokenId,
        uint256 _quantity,
        address _nftAddress,
        address _sellerAddress
    ) internal {
        Sale storage NftForSale = mapSale[_nftAddress][_tokenId][
            _sellerAddress
        ];

        require(
            NftForSale.quantity > 0,
            "Buy Nfts:No NFT is availabe for purchase"
        );
        require(
            msg.sender != NftForSale.seller,
            "Buy Nfts: Owner Is Not Allowed To Buy Nfts"
        );
        require(
            _quantity <= NftForSale.quantity,
            "Buy Nfts: Exceeds max quantity"
        );
        require(!_isAdmin(), "Buy Nfts: Admin Cannot Buy Nfts");

        uint256 buyAmount = NftForSale.price.mul(_quantity);
        address buyer = msg.sender;

        if (NftForSale.erc20Token == address(0)) {
            require(msg.value >= buyAmount, "Buy Nfts: Insufficient fund");
            //else means for erc20 token
        } else {
            require(
                IERC20(NftForSale.erc20Token).allowance(buyer, address(this)) >=
                    buyAmount,
                "Less allowance"
            );

            IERC20(NftForSale.erc20Token).safeTransferFrom(
                buyer,
                address(this),
                buyAmount
            );
        }
        _NftSale(
            _tokenId,
            _quantity,
            _nftAddress,
            buyAmount,
            buyer,
            NftForSale
        );
    }

    /**
     * @notice NftSaleFixedPriceFiat
     * Function to handle fixed price sale with fiat payment
     * @param _tokenId use to buy nfts on sell
     * @param _quantity Token Quantity
     * @param _nftAddress Take erc721 and erc1155 address
     * @param _sellerAddress Seller address
     * @param _buyer NFT receiver address
     */
    function _NftSaleFixedPriceFiat(
        uint256 _tokenId,
        uint256 _quantity,
        address _nftAddress,
        address _sellerAddress,
        address _buyer
    ) internal {
        Sale storage NftForSale = mapSale[_nftAddress][_tokenId][
            _sellerAddress
        ];

        require(
            NftForSale.quantity > 0,
            "Buy Nfts :No NFT is availabe for purchase"
        );
        require(
            _quantity <= NftForSale.quantity,
            "Buy Nfts: Exceeds max quantity"
        );

        uint256 buyAmount = NftForSale.price.mul(_quantity);
        address buyer = _buyer;

        _NftSale(
            _tokenId,
            _quantity,
            _nftAddress,
            buyAmount,
            buyer,
            NftForSale
        );
    }

    /**
     * @notice NftAuctionInstantBuy
     * Function to handle auction instant buy with direct payment
     * @param _tokenId use to buy nfts on sell
     * @param _nftAddress ERC721 or ERC1155 address
     * @param _auctioner Seller address
     */
    function _NftAuctionInstantBuy(
        uint256 _tokenId,
        address _nftAddress,
        address _auctioner
    ) internal {
        Auction storage NftOnAuction = mapAuction[_nftAddress][_tokenId][
            _auctioner
        ];

        require(
            NftOnAuction.quantity > 0,
            "Auction Instant Buy: Buy for non existing auction"
        );
        require(
            !_isAdmin(),
            "Auction Instant Buy: Admin not allowed to perform purchase"
        );

        require(
            msg.sender != NftOnAuction.auctioner,
            "Auction Instant Buy : Sellernot allowed to perform purchase"
        );
        require(
            NftOnAuction.salePrice > NftOnAuction.bidAmount,
            "Auction Instant Buy: bid exceeds sale price"
        );

        if (NftOnAuction.erc20Token == address(0)) {
            require(
                msg.value == NftOnAuction.salePrice,
                "Auction Instant Buy: Amount received and sale price should be same"
            );

            if (NftOnAuction.currentBidder != address(0)) {
                payable(NftOnAuction.currentBidder).transfer(
                    NftOnAuction.bidAmount
                );
            }
        } else {
            uint256 checkAllowance = IERC20(NftOnAuction.erc20Token).allowance(
                msg.sender,
                address(this)
            );

            require(
                checkAllowance >= NftOnAuction.salePrice,
                "Place Bid : Allowance is Less then Price"
            );

            IERC20(NftOnAuction.erc20Token).safeTransferFrom(
                msg.sender,
                address(this),
                NftOnAuction.salePrice
            );

            if (NftOnAuction.currentBidder != address(0)) {
                IERC20(NftOnAuction.erc20Token).safeTransfer(
                    NftOnAuction.currentBidder,
                    NftOnAuction.bidAmount
                );
            }
        }

        address buyer = msg.sender;

        _NftAuction(_tokenId, _nftAddress, _auctioner, buyer, NftOnAuction);
    }

    /**
     * @notice NftAuctionInstantBuyFiat
     * Function to handle auction instant sale with fiat payment
     * @param _tokenId use to buy nfts on sell
     * @param _nftAddress Take erc721 and erc1155 address
     * @param _auctioner Seller address
     * @param _buyer NFT receiver address
     */
    function _NftAuctionInstantBuyFiat(
        uint256 _tokenId,
        address _nftAddress,
        address _auctioner,
        address _buyer
    ) internal {
        Auction storage NftOnAuction = mapAuction[_nftAddress][_tokenId][
            _auctioner
        ];

        require(
            NftOnAuction.quantity > 0,
            "Auction Instant Buy: Buy for non existing auction"
        );
        require(
            !_isAdmin(),
            "Auction Instant Buy: Admin not allowed to perform purchase"
        );

        require(
            _buyer != NftOnAuction.auctioner,
            "Auction Instant Buy : Sellernot allowed to perform purchase"
        );
        require(
            NftOnAuction.salePrice > NftOnAuction.bidAmount,
            "Auction Instant Buy: bid exceeds sale price"
        );

        if (NftOnAuction.erc20Token == address(0)) {
            if (NftOnAuction.currentBidder != address(0)) {
                payable(NftOnAuction.currentBidder).transfer(
                    NftOnAuction.bidAmount
                );
            }
        } else {
            if (NftOnAuction.currentBidder != address(0)) {
                IERC20(NftOnAuction.erc20Token).safeTransfer(
                    NftOnAuction.currentBidder,
                    NftOnAuction.bidAmount
                );
            }
        }

        _NftAuction(_tokenId, _nftAddress, _auctioner, _buyer, NftOnAuction);
    }

    /**
     * @notice NftSale
     * Function to manage fixed price sale common logic
     * @param _tokenId use to buy nfts on sell
     * @param _quantity Token Quantity
     * @param _nftAddress Take erc721 and erc1155 address
     * @param _buyAmount Amount
     * @param _buyer NFT receiver address
     */
    function _NftSale(
        uint256 _tokenId,
        uint256 _quantity,
        address _nftAddress,
        uint256 _buyAmount,
        address _buyer,
        Sale memory NftForSale
    ) internal {
        if (IERC721(_nftAddress).supportsInterface(ERC721InterfaceId)) {
            require(
                _quantity == 1,
                "BuyNfts: ERC721Token accept only one token quantity"
            );
            //nft transfer
            IERC721(_nftAddress).transferFrom(address(this), _buyer, _tokenId);
        } else if (
            IERC1155(_nftAddress).supportsInterface(ERC1155InterfaceId)
        ) {
            //transfer nfts
            IERC1155(_nftAddress).safeTransferFrom(
                address(this),
                _buyer,
                _tokenId,
                _quantity,
                ""
            );
        }
        _payOut(
            _nftAddress,
            _buyAmount,
            NftForSale.erc20Token,
            NftForSale.seller,
            true
        );

        Sale storage nftOnSaleStorage = mapSale[_nftAddress][_tokenId][
            NftForSale.seller
        ];
        nftOnSaleStorage.quantity = nftOnSaleStorage.quantity - _quantity;

        if (NftForSale.quantity == 0) {
            delete mapSale[_nftAddress][_tokenId][NftForSale.seller];
        }
        emit NftSold(
            _tokenId,
            _nftAddress,
            NftForSale.seller,
            NftForSale.price,
            NftForSale.erc20Token,
            _buyer,
            _quantity
        );
    }

    /**
     * @notice NftAuction
     * Function to manage auction instant purchase general logic
     * @param _tokenId use to buy nfts on sell
     * @param _nftAddress Take erc721 and erc1155 address
     * @param _auctioner Seller address
     * @param _buyer NFT receiver address
     */
    function _NftAuction(
        uint256 _tokenId,
        address _nftAddress,
        address _auctioner,
        address _buyer,
        Auction memory NftOnAuction
    ) internal {
        if (IERC721(_nftAddress).supportsInterface(ERC721InterfaceId)) {
            IERC721(_nftAddress).transferFrom(
                address(this),
                msg.sender,
                _tokenId
            );
        } else if (
            IERC1155(_nftAddress).supportsInterface(ERC1155InterfaceId)
        ) {
            IERC1155(_nftAddress).safeTransferFrom(
                address(this),
                msg.sender,
                _tokenId,
                NftOnAuction.quantity,
                ""
            );
        }

        _payOut(
            _nftAddress,
            NftOnAuction.salePrice,
            NftOnAuction.erc20Token,
            NftOnAuction.auctioner,
            true
        );

        emit AuctionSettled(
            NftOnAuction.tokenId,
            _nftAddress,
            _auctioner,
            _buyer,
            NftOnAuction.erc20Token,
            NftOnAuction.quantity,
            NftOnAuction.salePrice
        );

        delete mapAuction[_nftAddress][_tokenId][_auctioner];
    }

    /**
     * @notice isNFT
     * Function to check if the given address is an NFT.
     * Checks for ERC721 or ERC1155 interface support
     * @param _nftAddress Take erc721 and erc1155 address
     * @return bool
     */
    function _isNFT(address _nftAddress) internal view returns (bool) {
        return (IERC721(_nftAddress).supportsInterface(ERC721InterfaceId) ||
            IERC1155(_nftAddress).supportsInterface(ERC1155InterfaceId));
    }

    /**
     * @notice hashFixedPriceTypedData
     * To hash the nft fixed price metadata
     * @param tokenId NFT unique ID
     * @param seller Seller address
     * @param nftAddress ERC721 or ERC1155 address
     * @return Hash Hash of metadata
     */
    function _hashFixedPriceTypedData(
        uint256 tokenId,
        address seller,
        address nftAddress
    ) internal view returns (bytes32) {
        Sale storage NftForSale = mapSale[nftAddress][tokenId][seller];
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        FIXED_PRICE_TYPEHASH,
                        tokenId,
                        NftForSale.price,
                        NftForSale.quantity,
                        NftForSale.erc20Token,
                        NftForSale.seller,
                        nftAddress
                    )
                )
            );
    }

    /**
     * @notice hashAuctionTypedData
     * To hash the nft auction metadata
     * @param tokenId NFT unique ID
     * @param auctioner Seller address
     * @param nftAddress ERC721 or ERC1155 address
     * @return Hash Hash of metadata
     */
    function _hashAuctionTypedData(
        uint256 tokenId,
        address auctioner,
        address nftAddress
    ) internal view returns (bytes32) {
        Auction storage NftOnAuction = mapAuction[nftAddress][tokenId][
            auctioner
        ];
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        AUCTION_TYPEHASH,
                        tokenId,
                        NftOnAuction.basePrice,
                        NftOnAuction.salePrice,
                        NftOnAuction.quantity,
                        NftOnAuction.erc20Token,
                        NftOnAuction.auctioner,
                        nftAddress
                    )
                )
            );
    }

    /**
     * @notice getSigner
     * To extract signer address from signature
     * @param digest Data hash
     * @param signature Signature
     * @return Signer Signer address
     */
    function _getSigner(
        bytes32 digest,
        bytes memory signature
    ) internal pure returns (address) {
        address signer = ECDSA.recover(digest, signature);
        return signer;
    }

    /**
     * @notice verifySignature
     * To peerform signature verification
     * @param _tokenId NFT unique ID
     * @param _auctioner Seller address
     * @param _nftAddress ERC721 or ERC1155 address
     * @param _signature Metadata signed by admin during NFT creation on platform
     * @return boolean Verification status
     */
    function _verifySignature(
        uint256 _tokenId,
        address _auctioner,
        address _nftAddress,
        uint256 _saleType,
        bytes calldata _signature
    ) internal view returns (bool) {
        address signer;
        if (_saleType == TYPE_SALE) {
            signer = _getSigner(
                _hashFixedPriceTypedData(_tokenId, _auctioner, _nftAddress),
                _signature
            );
        } else if (_saleType == TYPE_AUCTION) {
            signer = _getSigner(
                _hashAuctionTypedData(_tokenId, _auctioner, _nftAddress),
                _signature
            );
        }
        require(
            hasRole(ADMIN_ROLE, signer) || hasRole(DEFAULT_ADMIN_ROLE, signer),
            "Signature verification failed!"
        );
        return true;
    }

    /**
     * @notice Receive fund to this contract, usually for the purpose of fiat on-ramp
     * for EOA transfer
     */
    receive() external payable {
        emit FundReceived(msg.sender, msg.value);
    }

    /**
     * @notice Receive fund to this contract, usually for the purpose of fiat on-ramp
     * for contract transfer
     */
    fallback() external payable {
        emit FundReceived(msg.sender, msg.value);
    }
}
