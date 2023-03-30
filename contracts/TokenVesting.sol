// contracts/TokenVesting.sol
// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.18;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";

/// @title TokenVesting - On-Chain vesting scheme enabled by smart contracts.
/// The TokenVesting contract can release its token balance gradually like a
/// typical vesting scheme, with a cliff and vesting period. The contract owner
/// can create vesting schedules for different users, even multiple for the same person.
/// Vesting schedules are optionally revokable by the owner. Additionally the
/// smart contract functions as an ERC20 compatible non-transferable virtual
/// token which can be used e.g. for governance.
/// This work is based on the TokenVesting contract by Abdelhamid Bakhta
/// (https://github.com/abdelhamidbakhta/token-vesting-contracts)
/// and was extended with the virtual token functionality and partially rewritten.
/// @author Schmackofant - schmackofant@protonmail.com

contract TokenVesting is IERC20Metadata, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20Metadata;

    /// @notice The ERC20 name of the virtual token
    string public override name;

    /// @notice The ERC20 symbol of the virtual token
    string public override symbol;

    /// @notice The ERC20 number of decimals of the virtual token
    /// @dev This contract only supports native tokens with 18 decimals
    uint8 public constant override decimals = 18;

    enum Status {
        INITIALIZED, //0
        REVOKED
    }

    /**
     * @dev vesting schedule struct
     * @param cliff cliff period in seconds
     * @param start start time of the vesting period
     * @param duration duration of the vesting period in seconds
     * @param slicePeriodSeconds duration of a slice period for the vesting in seconds
     * @param amountTotal total amount of tokens to be released at the end of the vesting
     * @param released amount of tokens released so far
     * @param status schedule status (initialized, revoked)
     * @param beneficiary address of beneficiary of the vesting schedule
     * @param revokable whether or not the vesting is revokable
     */
    struct VestingSchedule {
        uint256 cliff;
        uint256 start;
        uint256 duration;
        uint256 slicePeriodSeconds;
        uint256 amountTotal;
        uint256 released;
        Status status;
        address beneficiary;
        bool revokable;
    }

    /// @notice address of the ERC20 native token
    IERC20Metadata public immutable nativeToken;

    /// @dev This mapping is used to keep track of the vesting schedule ids
    bytes32[] public vestingSchedulesIds;

    /// @dev This mapping is used to keep track of the vesting schedules
    mapping(bytes32 => VestingSchedule) private vestingSchedules;

    /// @notice total amount of native tokens in all vesting schedules
    uint256 public vestingSchedulesTotalAmount;

    /// @notice This mapping is used to keep track of the number of vesting schedules for each beneficiary
    mapping(address => uint256) public holdersVestingScheduleCount;

    /// @dev This mapping is used to keep track of the total amount of vested tokens for each beneficiary
    mapping(address => uint256) private holdersVestedAmount;

    event Released(bytes32 vestingSchedule, address beneficiary, uint256 amount);
    event Revoked(bytes32 vestingSchedule);

    /**
     * @dev Reverts if the vesting schedule does not exist or has been revoked.
     */
    modifier onlyIfVestingScheduleNotRevoked(bytes32 vestingScheduleId) {
        //slither-disable-next-line incorrect-equality
        require(vestingSchedules[vestingScheduleId].status == Status.INITIALIZED);
        _;
    }

    /// @dev This error is fired when trying to perform an action that is not
    /// supported by the contract, like transfers and approvals. These actions
    /// will never be supported.
    error NotSupported();

    error DecimalsError();

    /**
     * @notice Creates a vesting contract.
     * @param token_ address of the ERC20 native token contract
     * @param _name name of the virtual token
     * @param _symbol symbol of the virtual token
     */
    constructor(IERC20Metadata token_, string memory _name, string memory _symbol) {
        nativeToken = IERC20Metadata(token_);
        if (nativeToken.decimals() != 18) revert DecimalsError();
        name = _name;
        symbol = _symbol;
    }

    /**
     * @dev This function is called for plain Ether transfers, i.e. for every call with empty calldata.
     */
    receive() external payable { }

    /**
     * @dev Fallback function is executed if none of the other functions match the function
     * identifier or no data was provided with the function call.
     */
    fallback() external payable { }

    /// @dev All types of transfers are permanently disabled.
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert NotSupported();
    }

    /// @dev All types of transfers are permanently disabled.
    function transfer(address, uint256) public pure override returns (bool) {
        revert NotSupported();
    }

    /// @dev All types of approvals are permanently disabled to reduce code
    /// size.
    function approve(address, uint256) public pure override returns (bool) {
        revert NotSupported();
    }

    /// @dev Approvals cannot be set, so allowances are always zero.
    function allowance(address, address) public pure override returns (uint256) {
        return 0;
    }

    /// @notice Returns the amount of virtual tokens in existence
    function totalSupply() public view override returns (uint256) {
        return vestingSchedulesTotalAmount;
    }

    /// @notice Returns the sum of virtual tokens for a user
    /// @param user The user for whom the balance is calculated
    /// @return Balance of the user
    function balanceOf(address user) public view override returns (uint256) {
        return holdersVestedAmount[user];
    }

    /**
     * @notice Returns the vesting schedule information for a given holder and index.
     * @return the vesting schedule structure information
     */
    function getVestingScheduleByAddressAndIndex(address holder, uint256 index) external view returns (VestingSchedule memory) {
        return getVestingSchedule(computeVestingScheduleIdForAddressAndIndex(holder, index));
    }

    /**
     * @notice Public function for creating a vesting schedule (only callable by contract owner)
     * @param _beneficiary address of the beneficiary to whom vested tokens are transferred
     * @param _start start time of the vesting period
     * @param _cliff duration in seconds of the cliff in which tokens will begin to vest
     * @param _duration duration in seconds of the period in which the tokens will vest
     * @param _slicePeriodSeconds duration of a slice period for the vesting in seconds
     * @param _revokable whether the vesting is revokable or not
     * @param _amount total amount of tokens to be released at the end of the vesting
     */
    function createVestingSchedule(
        address _beneficiary,
        uint256 _start,
        uint256 _cliff,
        uint256 _duration,
        uint256 _slicePeriodSeconds,
        bool _revokable,
        uint256 _amount
    ) external onlyOwner {
        _createVestingSchedule(_beneficiary, _start, _cliff, _duration, _slicePeriodSeconds, _revokable, _amount);
    }

    /**
     * @notice Creates a new vesting schedule for a beneficiary.
     * @param _beneficiary address of the beneficiary to whom vested tokens are transferred
     * @param _start start time of the vesting period
     * @param _cliff duration in seconds of the cliff in which tokens will begin to vest
     * @param _duration duration in seconds of the period in which the tokens will vest
     * @param _slicePeriodSeconds duration of a slice period for the vesting in seconds
     * @param _revokable whether the vesting is revokable or not
     * @param _amount total amount of tokens to be released at the end of the vesting
     */
    function _createVestingSchedule(
        address _beneficiary,
        uint256 _start,
        uint256 _cliff,
        uint256 _duration,
        uint256 _slicePeriodSeconds,
        bool _revokable,
        uint256 _amount
    ) internal {
        require(getWithdrawableAmount() >= _amount, "TokenVesting: cannot create vesting schedule because of insufficient tokens in contract");
        require(_duration != 0, "TokenVesting: duration must not be 0");
        require(_amount != 0, "TokenVesting: amount must not be 0");
        require(_slicePeriodSeconds >= 1, "TokenVesting: slicePeriodSeconds must be >= 1");
        require(_duration >= _cliff, "TokenVesting: duration must be >= cliff");
        require(_amount <= 2 ** 200, "TokenVesting: amount must be <= 2 ** 200");
        require(_duration <= 50 * 365 * 24 * 60 * 60, "TokenVesting: duration must be <= 50 years");
        bytes32 vestingScheduleId = computeNextVestingScheduleIdForHolder(_beneficiary);
        uint256 cliff = _start + _cliff;
        vestingSchedules[vestingScheduleId] =
            VestingSchedule(cliff, _start, _duration, _slicePeriodSeconds, _amount, 0, Status.INITIALIZED, _beneficiary, _revokable);
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount + _amount;
        vestingSchedulesIds.push(vestingScheduleId);
        uint256 currentVestingCount = holdersVestingScheduleCount[_beneficiary];
        holdersVestingScheduleCount[_beneficiary] = currentVestingCount + 1;
        holdersVestedAmount[_beneficiary] = holdersVestedAmount[_beneficiary] + _amount;
    }

    /**
     * @notice Revokes the vesting schedule for given identifier.
     * @param vestingScheduleId the vesting schedule identifier
     */
    function revoke(bytes32 vestingScheduleId) external onlyOwner onlyIfVestingScheduleNotRevoked(vestingScheduleId) {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        require(vestingSchedule.revokable, "TokenVesting: vesting is not revokable");
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        if (vestedAmount > 0) {
            _release(vestingScheduleId, vestedAmount);
        }
        uint256 unreleased = vestingSchedule.amountTotal - vestingSchedule.released;
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount - unreleased;
        holdersVestedAmount[vestingSchedule.beneficiary] = holdersVestedAmount[vestingSchedule.beneficiary] - unreleased;
        vestingSchedule.status = Status.REVOKED;
        emit Revoked(vestingScheduleId);
    }

    /**
     * @notice Pauses or unpauses the release of tokens and claiming of schedules
     * @param paused true if the release of tokens and claiming of schedules should be paused, false otherwise
     */
    function setPaused(bool paused) external onlyOwner {
        if (paused) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**
     * @notice Withdraw the specified amount if possible.
     * @param amount the amount to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant onlyOwner {
        require(getWithdrawableAmount() >= amount, "TokenVesting: not enough withdrawable funds");
        nativeToken.safeTransfer(owner(), amount);
    }

    /**
     * @notice Internal function for releasing vested amount of tokens.
     * @param vestingScheduleId the vesting schedule identifier
     * @param amount the amount to release
     */
    function _release(bytes32 vestingScheduleId, uint256 amount) internal whenNotPaused {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        bool isBeneficiary = msg.sender == vestingSchedule.beneficiary;
        bool isOwner = msg.sender == owner();
        require(isBeneficiary || isOwner, "TokenVesting: only beneficiary and owner can release vested tokens");
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        require(vestedAmount >= amount, "TokenVesting: cannot release tokens, not enough vested tokens");
        vestingSchedule.released = vestingSchedule.released + amount;
        address beneficiaryPayable = vestingSchedule.beneficiary;
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount - amount;
        holdersVestedAmount[vestingSchedule.beneficiary] = holdersVestedAmount[vestingSchedule.beneficiary] - amount;
        emit Released(vestingScheduleId, vestingSchedule.beneficiary, amount);
        nativeToken.safeTransfer(beneficiaryPayable, amount);
    }

    /**
     * @notice Release vested amount of tokens.
     * @param vestingScheduleId the vesting schedule identifier
     * @param amount the amount to release
     */
    function release(bytes32 vestingScheduleId, uint256 amount)
        external
        whenNotPaused
        nonReentrant
        onlyIfVestingScheduleNotRevoked(vestingScheduleId)
    {
        _release(vestingScheduleId, amount);
    }

    /**
     * @notice Release all available tokens for holder address
     * @param holder address of the holder & beneficiary
     */
    function releaseAvailableTokensForHolder(address holder) external whenNotPaused nonReentrant {
        require(msg.sender == holder || msg.sender == owner(), "TokenVesting: only beneficiary and owner can release vested tokens");
        uint256 vestingScheduleCount = holdersVestingScheduleCount[holder];
        for (uint256 i = 0; i < vestingScheduleCount; i++) {
            bytes32 vestingScheduleId = computeVestingScheduleIdForAddressAndIndex(holder, i);
            uint256 releasable = computeReleasableAmount(vestingScheduleId);
            if (releasable > 0) {
                _release(vestingScheduleId, releasable);
            }
        }
    }

    /**
     * @notice Returns the array of vesting schedule ids
     * @return vestingSchedulesIds
     */
    function getVestingSchedulesIds() public view returns (bytes32[] memory) {
        return vestingSchedulesIds;
    }

    /**
     * @notice Computes the vested amount of tokens for the given vesting schedule identifier.
     * @return the vested amount
     */
    function computeReleasableAmount(bytes32 vestingScheduleId) public view onlyIfVestingScheduleNotRevoked(vestingScheduleId) returns (uint256) {
        return _computeReleasableAmount(vestingSchedules[vestingScheduleId]);
    }

    /**
     * @notice Returns the vesting schedule information for a given identifier.
     * @return the vesting schedule structure information
     */
    function getVestingSchedule(bytes32 vestingScheduleId) public view returns (VestingSchedule memory) {
        return vestingSchedules[vestingScheduleId];
    }

    /**
     * @notice Returns the amount of native tokens that can be withdrawn by the owner.
     * @return the amount of tokens
     */
    function getWithdrawableAmount() public view returns (uint256) {
        return nativeToken.balanceOf(address(this)) - vestingSchedulesTotalAmount;
    }

    /**
     * @notice Computes the next vesting schedule identifier for a given holder address.
     */
    function computeNextVestingScheduleIdForHolder(address holder) public view returns (bytes32) {
        return computeVestingScheduleIdForAddressAndIndex(holder, holdersVestingScheduleCount[holder]);
    }

    /**
     * @notice Computes the vesting schedule identifier for an address and an index.
     */
    function computeVestingScheduleIdForAddressAndIndex(address holder, uint256 index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(holder, index));
    }

    /**
     * @dev Computes the releasable amount of tokens for a vesting schedule.
     * @return the amount of releasable tokens
     */
    function _computeReleasableAmount(VestingSchedule memory vestingSchedule) internal view returns (uint256) {
        uint256 currentTime = block.timestamp;
        //slither-disable-next-line incorrect-equality
        if (currentTime < vestingSchedule.cliff || vestingSchedule.status == Status.REVOKED) {
            return 0;
        } else if (currentTime >= vestingSchedule.start + vestingSchedule.duration) {
            return vestingSchedule.amountTotal - vestingSchedule.released;
        } else {
            uint256 timeFromStart = currentTime - vestingSchedule.start;
            uint256 secondsPerSlice = vestingSchedule.slicePeriodSeconds;
            uint256 vestedSlicePeriods = timeFromStart / secondsPerSlice;
            // Disable warning: duration and token amounts are checked in schedule creation and prevent underflow/overflow
            //slither-disable-next-line divide-before-multiply
            uint256 vestedSeconds = vestedSlicePeriods * secondsPerSlice;
            // Disable warning: duration and token amounts are checked in schedule creation and prevent underflow/overflow
            //slither-disable-next-line divide-before-multiply
            uint256 vestedAmount = vestingSchedule.amountTotal * vestedSeconds / vestingSchedule.duration;
            vestedAmount = vestedAmount - vestingSchedule.released;
            return vestedAmount;
        }
    }
}
