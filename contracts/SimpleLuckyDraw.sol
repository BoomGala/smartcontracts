//SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract SimpleLuckyDraw is Ownable, VRFConsumerBase, AccessControl {
    bytes32 internal keyHash;
    uint256 internal fee;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    mapping(uint => Round) private roundMapping;
    uint public currentRound = 1;

    enum RoundStatus {
        PREPRATION,
        DRAWN,
        DONE
    }

    struct Round {
        bytes32 requestId;
        uint lowerBound;
        uint upperBound;
        uint randomness;
        uint[] winningNumbers;
        mapping(uint => bool) exists;
        RoundStatus status;
    }

    event Draw(uint indexed roundNumber, uint drawNo, uint[] winningNumbers);
    event NewRound(uint indexed roundNumber);
    event RequestedRandomness(uint indexed roundNumber, bytes32 requestId);

    constructor(address vrfCoordinator_, address linkToken_, bytes32 keyHash_, uint fees_)
        VRFConsumerBase(
            vrfCoordinator_,
            linkToken_
        )
    {
        keyHash = keyHash_;
        fee = fees_;
        _setupRole(ADMIN_ROLE, msg.sender);

        Round storage _cRound = roundMapping[currentRound];
        _cRound.status = RoundStatus.PREPRATION;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not admin");
        _;
    }

    function setupRound(uint _lowerBound, uint _upperBound) external onlyAdmin {
        require(_lowerBound > 0 && _upperBound > 0 && _upperBound > _lowerBound, "lower/upper Bound setup is not correct!");

        Round storage _cRound = roundMapping[currentRound];
        require(_cRound.status == RoundStatus.PREPRATION, "The round must be PREPRATION!");

        _cRound.lowerBound = _lowerBound;
        _cRound.upperBound = _upperBound;

    }

    function requestRandomness() external onlyAdmin {
        Round storage _round = roundMapping[currentRound];
        require(_round.status == RoundStatus.PREPRATION, "The round must be PREPRATION!");
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK to cover the fee!");

        bytes32 _requestId = requestRandomness(keyHash, fee);
        _round.requestId = _requestId;

        emit RequestedRandomness(currentRound, _requestId);
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        Round storage _round = roundMapping[currentRound];

        require(_round.status == RoundStatus.PREPRATION, "The round must be PREPRATION!");
        require(_round.requestId == requestId, "The VRF requestId is not matched!");

        _round.randomness = randomness;
        _round.status = RoundStatus.DRAWN;
    }

    function luckyDraw(uint _drawNo) external onlyAdmin {
        require(_drawNo > 0 && _drawNo <= 200, "Exceeds txn gas limits?");

        Round storage _round = roundMapping[currentRound];
        require(_round.status == RoundStatus.DRAWN, "The round must be DRAWN.");

        uint randomness = _round.randomness;
        require(randomness > 0, "Randomness are not fullfilled!");

        uint _lowerBound = _round.lowerBound;
        uint _upperBound = _round.upperBound;
        uint[] storage _winningNumbers = _round.winningNumbers;
        mapping(uint => bool) storage _exists = _round.exists;
        uint modNumber = _upperBound - _lowerBound;

        for (uint i = 0; i < _drawNo; i++) {
            uint randomNumber = uint(keccak256(abi.encode(randomness, block.number, block.difficulty, i)));
            uint luckyNumber = (randomNumber % modNumber) + _lowerBound;

            while(_exists[luckyNumber]) {
                luckyNumber ++;
                if (luckyNumber > _upperBound) {
                    luckyNumber = _lowerBound;
                }
            }

            _exists[luckyNumber] = true;
            _winningNumbers.push(luckyNumber);
        }

        emit Draw(currentRound, _drawNo, _winningNumbers);
    }

    function getWinningNumbers(uint round) public view returns (uint[] memory) {
        Round storage _cRound = roundMapping[round];
        require(_cRound.status == RoundStatus.DRAWN || _cRound.status == RoundStatus.DONE, "The round must be DRAWN or DONE.");
        return _cRound.winningNumbers;
    }

    function openNewRound() external onlyAdmin {
        Round storage _cRound = roundMapping[currentRound];
        require(_cRound.status == RoundStatus.DRAWN, "The round must be DRAWN.");
        _cRound.status = RoundStatus.DONE;

        currentRound ++;
        Round storage _round = roundMapping[currentRound];
        _round.status = RoundStatus.PREPRATION;

        emit NewRound(currentRound);
    }

    function addAdmin(address newAdmin) external onlyOwner {
      _setupRole(ADMIN_ROLE, newAdmin);
    }

    function getCurrentRoundInfo() view external returns (RoundStatus status, bool fetchedRandomness) {
      Round storage _cRound = roundMapping[currentRound];
      return (_cRound.status, _cRound.randomness > 0);
    }

}
