// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @dev {ERC721} token, including:
 *
 *  - ability for holders to burn (destroy) their tokens
 *  - a minter role that allows for token minting (creation)
 *  - a pauser role that allows to stop all token transfers
 *  - token ID and URI autogeneration
 *
 * This contract uses {AccessControl} to lock permissioned functions using the
 * different roles - head to its documentation for details.
 *
 * The account that deploys the contract will be granted the minter and pauser
 * roles, as well as the default admin role, which will let it grant both minter
 * and pauser roles to other accounts.
 */
contract Erc721NftContract is
    AccessControlEnumerable,
    Ownable,
    ERC721Enumerable,
    ERC721Burnable,
    ERC721Pausable
{
    using Strings for uint256;

    constructor(
        string memory name,
        string memory symbol,
        string memory baseTokenURI,
        address rootAdmin
    ) ERC721(name, symbol) {
        _baseTokenURI = baseTokenURI;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, rootAdmin);
        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);
    }

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    string private _baseTokenURI;

    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    mapping(uint256 => string) private _tokenURIs;

    struct Royalties {
        address account;
        uint256 percentage;
    }

    // storing the royalty details of a token
    mapping(uint256 => Royalties) private _royalties;
    string private _contractURI;

    event RoyaltyAdded(
        uint256 indexed tokenId,
        address indexed account,
        uint256 percentage
    );

    /**
     * @notice  .
     * @dev     .
     * @return  string  .
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function updateBaseURI(string memory baseTokenURI) public onlyOwner {
        _baseTokenURI = baseTokenURI;
    }

    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    function updateContractURI(string memory uri) public onlyOwner {
        _contractURI = uri;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory metaUrl) {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        string memory _tokenURI = _tokenURIs[tokenId];

        // If there is no base URI, return the token URI.
        if (bytes(_baseTokenURI).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_baseTokenURI).length > 0) {
            if (bytes(_tokenURI).length == 0) {
                // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
                return
                    string(abi.encodePacked(_baseTokenURI, tokenId.toString()));
            }

            return string(abi.encodePacked(_baseTokenURI, _tokenURI));
        }
    }

    /**
     * @dev Sets `_tokenURI` as the tokenURI of `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _setTokenURI(
        uint256 tokenId,
        string memory _tokenURI
    ) internal virtual {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI set of nonexistent token"
        );

        bytes memory tempBytes = bytes(_tokenURI);
        if (tempBytes.length > 0) _tokenURIs[tokenId] = _tokenURI;
    }

    /**
     * @dev overriding the inherited {transferOwnership} function to reflect the admin changes into the {DEFAULT_ADMIN_ROLE}
     */
    function transferOwnership(address newOwner) public override onlyOwner {
        super.transferOwnership(newOwner);
        _setupRole(DEFAULT_ADMIN_ROLE, newOwner);
        renounceRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /**
     * @dev overriding the inherited {grantRole} function to have a single root admin
     */
    function grantRole(
        bytes32 role,
        address account
    ) public override(IAccessControl, AccessControl) {
        if (role == ADMIN_ROLE)
            require(
                getRoleMemberCount(ADMIN_ROLE) == 0,
                "exactly one address can have admin role"
            );

        super.grantRole(role, account);
    }

    /**
     * @dev modifier to check admin rights.
     * contract owner and root admin have admin rights
     */
    modifier onlyAdmin() {
        require(
            hasRole(ADMIN_ROLE, _msgSender()) || owner() == _msgSender(),
            "Restricted to admin."
        );
        _;
    }

    /**
     * @dev modifier to check mint rights.
     * contract owner, root admin and minter's have mint rights
     */
    modifier onlyMinter() {
        require(
            hasRole(ADMIN_ROLE, _msgSender()) ||
                hasRole(MINTER_ROLE, _msgSender()) ||
                owner() == _msgSender(),
            "Restricted to minter."
        );
        _;
    }

    /**
     * @dev modifier to check pause rights.
     * contract owner, root admin and pausers's have pause rights
     */
    modifier onlyPauser() {
        require(
            hasRole(ADMIN_ROLE, _msgSender()) ||
                hasRole(PAUSER_ROLE, _msgSender()) ||
                owner() == _msgSender(),
            "Restricted to pauser."
        );
        _;
    }

    /**
     * @dev This function is to change the root admin
     * exaclty one root admin is allowed per contract
     * only contract owner have the authority to add, remove or change
     */
    function changeRootAdmin(address newAdmin) public {
        address oldAdmin = getRoleMember(ADMIN_ROLE, 0);
        revokeRole(ADMIN_ROLE, oldAdmin);
        grantRole(ADMIN_ROLE, newAdmin);
    }

    /**
     * @dev This function is to add a minter or pauser into the contract,
     * only root admin and contract owner have the authority to add them
     * but only the root admin can revoke them using {revokeRole}
     * minter or pauser can also self renounce the access using {renounceRole}
     */
    function addMinterOrPauser(address account, bytes32 role) public onlyAdmin {
        if (role == MINTER_ROLE || role == PAUSER_ROLE)
            _setupRole(role, account);
    }

    // As part of the lazy minting this mint function will be called by the admin and will transfer the NFT to the buyer
    function mint(
        address receiver,
        uint256 collectibleId,
        string memory IPFSHash,
        Royalties calldata royalties
    ) public onlyMinter {
        _mint(receiver, collectibleId);
        _setTokenURI(collectibleId, IPFSHash);
        _setRoyalties(collectibleId, royalties);
    }

    function _setRoyalties(
        uint256 collectibleId,
        Royalties calldata royalties
    ) internal virtual {
        require(
            royalties.percentage <= 2000,
            "exceeds royalty collective max value of twenty percent"
        );
        // require(royalties.percentage >= 500, "subceed royalty collective min value of five percent");

        if (royalties.account != address(0)) {
            _royalties[collectibleId] = royalties;
            emit RoyaltyAdded(
                collectibleId,
                royalties.account,
                royalties.percentage
            );
        }
    }

    function royaltyInfo(
        uint256 _tokenId,
        uint256 _salePrice
    ) external view returns (address receiver, uint256 royaltyAmount) {
        require(_exists(_tokenId), "query for non nonexistent token");

        royaltyAmount = (_salePrice * _royalties[_tokenId].percentage) / 10000;
        receiver = _royalties[_tokenId].account;
    }

    /**
     * @dev This funtion is to give authority to root admin to transfer token to the
     * buyer on behalf of the token owner
     *
     * The token owner can approve and renounce the access via this function
     */
    function setApprovalForOwner(bool approval) public {
        address defaultAdmin = getRoleMember(ADMIN_ROLE, 0);
        setApprovalForAll(defaultAdmin, approval);
    }

    /**
     * @dev This funtion is to give authority to minter to transfer token to the
     * buyer on behalf of the token owner
     *
     * The token owner can approve and renounce the access via this function
     */
    function setApprovalForMinter(bool approval, address minterAccount) public {
        require(hasRole(MINTER_ROLE, minterAccount), "not a minter address");
        setApprovalForAll(minterAccount, approval);
    }

    /**
     * @dev This funtion is to check weather the contract admin have approval from a token owner
     *
     */
    function isApprovedForOwner(
        address account
    ) public view returns (bool approval) {
        address defaultAdmin = getRoleMember(ADMIN_ROLE, 0);
        return isApprovedForAll(account, defaultAdmin);
    }

    /**
     * @dev Pauses all token transfers.
     *
     * See {ERC721Pausable} and {Pausable-_pause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function pause() public virtual onlyPauser {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers.
     *
     * See {ERC721Pausable} and {Pausable-_unpause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function unpause() public virtual onlyPauser {
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override(ERC721, ERC721Enumerable, ERC721Pausable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(AccessControlEnumerable, ERC721, ERC721Enumerable)
        returns (bool)
    {
        // add support to EIP-2981: NFT Royalty Standard
        if (interfaceId == _INTERFACE_ID_ERC2981) {
            return true;
        }
        return super.supportsInterface(interfaceId);
    }

    uint256[48] private __gap;
}
