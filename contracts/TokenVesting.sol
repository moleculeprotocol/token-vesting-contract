// contracts/TokenVesting.sol
// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";

abstract contract IERC20Extended is IERC20 {
    function decimals() public virtual returns (uint8);
}

/// @title TokenVesting - This contract enables the storage of
/// tokens alongside a vesting schdule that release a subset
/// of the total amount stored on a time schedule. This implementation
/// also allows the owner to revoke a given schedule's tokens
/// in the case that a beneficiary does not meet the vesting
/// requirement.
/// Original repository can be found at:
/// https://github.com/abdelhamidbakhta/token-vesting-contracts
/// @author Abdelhamid Bakhta - abdelhamid.bakhta@gmail.com
contract TokenVesting is IERC20, Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20Extended;

    /// @dev The ERC20 name of the virtual token
    string public name;
    /// @dev The ERC20 symbol of the virtual token
    string public symbol;
    /// @dev The ERC20 number of decimals of the virtual token (this contract only supports native tokens with 18 decimals)
    uint8 public constant decimals = 18;

    enum Status {
        INITIALIZED, //0
        REVOKED
    }

    struct VestingSchedule {
        // beneficiary of tokens after they are released
        address beneficiary;
        // cliff period in seconds
        uint256 cliff;
        // start time of the vesting period
        uint256 start;
        // duration of the vesting period in seconds
        uint256 duration;
        // duration of a slice period for the vesting in seconds
        uint256 slicePeriodSeconds;
        // whether or not the vesting is revokable
        bool revokable;
        // total amount of tokens to be released at the end of the vesting
        uint256 amountTotal;
        // amount of tokens released
        uint256 released;
        // schedule status (initialized, revoked)
        Status status;
    }

    // address of the ERC20 native token
    IERC20Extended private immutable _nativeToken;

    bytes32[] private vestingSchedulesIds;
    mapping(bytes32 => VestingSchedule) private vestingSchedules;
    uint256 private vestingSchedulesTotalAmount;

    // This mapping is used to keep track of the number of vesting schedules for each beneficiary
    mapping(address => uint256) private holdersVestingScheduleCount;

    // This mapping is used to keep track of the total amount of vested tokens for each beneficiary
    mapping(address => uint256) private holdersVestedAmount;

    event Released(bytes32 vestingSchedule, address beneficiary, uint256 amount);
    event Revoked(bytes32 vestingSchedule);

    /**
     * @dev Reverts if the vesting schedule does not exist or has been revoked.
     */
    modifier onlyIfVestingScheduleNotRevoked(bytes32 vestingScheduleId) {
        require(vestingSchedules[vestingScheduleId].status == Status.INITIALIZED);
        _;
    }

    /// @dev This error is fired when trying to perform an action that is not
    /// supported by the contract, like transfers and approvals. These actions
    /// will never be supported.
    error NotSupported();

    /**
     * @dev Creates a vesting contract.
     * @param token_ address of the ERC20 native token contract
     * @param _name name of the virtual token
     * @param _symbol symbol of the virtual token
     */
    constructor(address token_, string memory _name, string memory _symbol) {
        require(token_ != address(0x0));
        _nativeToken = IERC20Extended(token_);
        require(_nativeToken.decimals() == 18, "TokenVesting: only native tokens with 18 decimals are supported");
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
    function transferFrom(address, address, uint256) public pure returns (bool) {
        revert NotSupported();
    }

    /// @dev All types of transfers are permanently disabled.
    function transfer(address, uint256) public pure returns (bool) {
        revert NotSupported();
    }

    /// @dev All types of approvals are permanently disabled to reduce code
    /// size.
    function approve(address, uint256) public pure returns (bool) {
        revert NotSupported();
    }

    /// @dev Approvals cannot be set, so allowances are always zero.
    function allowance(address, address) public pure returns (uint256) {
        return 0;
    }

    /// @dev Returns the amount of virtual tokens in existence
    function totalSupply() public view returns (uint256) {
        return vestingSchedulesTotalAmount;
    }

    /// @dev Returns the sum of virtual tokens for a user
    /// @param user The user for whom the balance is calculated
    /// @return Balance of the user
    function balanceOf(address user) public view returns (uint256) {
        return holdersVestedAmount[user];
    }

    /**
     * @dev Returns the number of vesting schedules associated to a beneficiary.
     * @return the number of vesting schedules
     */
    function getVestingSchedulesCountByBeneficiary(address _beneficiary) external view returns (uint256) {
        return holdersVestingScheduleCount[_beneficiary];
    }

    /**
     * @dev Returns the vesting schedule id at the given index.
     * @return the vesting id
     */
    function getVestingIdAtIndex(uint256 index) external view returns (bytes32) {
        require(index < getVestingSchedulesCount(), "TokenVesting: index out of bounds");
        return vestingSchedulesIds[index];
    }

    /**
     * @notice Returns the vesting schedule information for a given holder and index.
     * @return the vesting schedule structure information
     */
    function getVestingScheduleByAddressAndIndex(address holder, uint256 index) external view returns (VestingSchedule memory) {
        return getVestingSchedule(computeVestingScheduleIdForAddressAndIndex(holder, index));
    }

    /**
     * @notice Returns the total amount of vesting schedules.
     * @return the total amount of vesting schedules
     */
    function getVestingSchedulesTotalAmount() external view returns (uint256) {
        return vestingSchedulesTotalAmount;
    }

    /**
     * @dev Returns the address of the ERC20 native token managed by the vesting contract.
     */
    function getNativeToken() external view returns (address) {
        return address(_nativeToken);
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
        require(_duration > 0, "TokenVesting: duration must be > 0");
        require(_amount > 0, "TokenVesting: amount must be > 0");
        require(_slicePeriodSeconds >= 1, "TokenVesting: slicePeriodSeconds must be >= 1");
        require(_duration >= _cliff, "TokenVesting: duration must be >= cliff");
        require(_amount <= 2 ** 200, "TokenVesting: amount must be <= 2 ** 200");
        require(_duration <= 50 * 365 * 24 * 60 * 60, "TokenVesting: duration must be <= 50 years");
        bytes32 vestingScheduleId = computeNextVestingScheduleIdForHolder(_beneficiary);
        uint256 cliff = _start.add(_cliff);
        vestingSchedules[vestingScheduleId] =
            VestingSchedule(_beneficiary, cliff, _start, _duration, _slicePeriodSeconds, _revokable, _amount, 0, Status.INITIALIZED);
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.add(_amount);
        vestingSchedulesIds.push(vestingScheduleId);
        uint256 currentVestingCount = holdersVestingScheduleCount[_beneficiary];
        holdersVestingScheduleCount[_beneficiary] = currentVestingCount.add(1);
        holdersVestedAmount[_beneficiary] = holdersVestedAmount[_beneficiary].add(_amount);
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
        uint256 unreleased = vestingSchedule.amountTotal.sub(vestingSchedule.released);
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.sub(unreleased);
        holdersVestedAmount[vestingSchedule.beneficiary] = holdersVestedAmount[vestingSchedule.beneficiary].sub(unreleased);
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
     * @notice Sets a new beneficiary for the vesting schedule for given identifier.
     * @param vestingScheduleId the vesting schedule identifier
     * @param newBeneficiary address of the new beneficiary
     */
    function changeBeneficiary(bytes32 vestingScheduleId, address newBeneficiary)
        external
        onlyOwner
        onlyIfVestingScheduleNotRevoked(vestingScheduleId)
    {
        require(newBeneficiary != address(0x0), "TokenVesting: new beneficiary must not be the zero address");
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        uint256 unreleased = vestingSchedule.amountTotal.sub(vestingSchedule.released);

        // Update the vested token amount for the old beneficiary by subtracting the unreleased amount
        holdersVestedAmount[vestingSchedule.beneficiary] = holdersVestedAmount[vestingSchedule.beneficiary].sub(unreleased);

        // Update the vested token amount for  the new beneficiary by adding the unreleased amount
        holdersVestedAmount[newBeneficiary] = holdersVestedAmount[newBeneficiary].add(unreleased);

        vestingSchedules[vestingScheduleId].beneficiary = newBeneficiary;
    }

    /**
     * @notice Withdraw the specified amount if possible.
     * @param amount the amount to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant onlyOwner {
        require(getWithdrawableAmount() >= amount, "TokenVesting: not enough withdrawable funds");
        _nativeToken.safeTransfer(owner(), amount);
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
        vestingSchedule.released = vestingSchedule.released.add(amount);
        address beneficiaryPayable = vestingSchedule.beneficiary;
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.sub(amount);
        holdersVestedAmount[vestingSchedule.beneficiary] = holdersVestedAmount[vestingSchedule.beneficiary].sub(amount);
        emit Released(vestingScheduleId, vestingSchedule.beneficiary, amount);
        _nativeToken.safeTransfer(beneficiaryPayable, amount);
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
     * @dev Returns the number of vesting schedules managed by this contract.
     * @return the number of vesting schedules
     */
    function getVestingSchedulesCount() public view returns (uint256) {
        return vestingSchedulesIds.length;
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
     * @dev Returns the amount of native tokens that can be withdrawn by the owner.
     * @return the amount of tokens
     */
    function getWithdrawableAmount() public view returns (uint256) {
        return _nativeToken.balanceOf(address(this)).sub(vestingSchedulesTotalAmount);
    }

    /**
     * @dev Computes the next vesting schedule identifier for a given holder address.
     */
    function computeNextVestingScheduleIdForHolder(address holder) public view returns (bytes32) {
        return computeVestingScheduleIdForAddressAndIndex(holder, holdersVestingScheduleCount[holder]);
    }

    /**
     * @dev Computes the vesting schedule identifier for an address and an index.
     */
    function computeVestingScheduleIdForAddressAndIndex(address holder, uint256 index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(holder, index));
    }

    /**
     * @dev Computes the releasable amount of tokens for a vesting schedule.
     * @return the amount of releasable tokens
     */
    function _computeReleasableAmount(VestingSchedule memory vestingSchedule) internal view returns (uint256) {
        uint256 currentTime = getCurrentTime();
        if ((currentTime < vestingSchedule.cliff) || vestingSchedule.status == Status.REVOKED) {
            return 0;
        } else if (currentTime >= vestingSchedule.start.add(vestingSchedule.duration)) {
            return vestingSchedule.amountTotal.sub(vestingSchedule.released);
        } else {
            uint256 timeFromStart = currentTime.sub(vestingSchedule.start);
            uint256 secondsPerSlice = vestingSchedule.slicePeriodSeconds;
            uint256 vestedSlicePeriods = timeFromStart.div(secondsPerSlice);
            uint256 vestedSeconds = vestedSlicePeriods.mul(secondsPerSlice);
            uint256 vestedAmount = vestingSchedule.amountTotal.mul(vestedSeconds).div(vestingSchedule.duration);
            vestedAmount = vestedAmount.sub(vestingSchedule.released);
            return vestedAmount;
        }
    }

    function getCurrentTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}
