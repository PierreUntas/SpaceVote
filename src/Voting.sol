// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/// @title VotingPlus - A decentralized voting system with multiple sessions support
/// @author SpaceVote Team
/// @notice This contract allows creating and managing multiple voting sessions with tie-breaking mechanism
/// @dev Inherits from OpenZeppelin's Ownable and Pausable contracts
contract VotingPlus is Ownable, Pausable {

    /// @notice Maximum number of proposals allowed per voting session
    uint public constant MAX_PROPOSALS = 100;

    /// @notice Maximum number of voters allowed per voting session
    uint public constant MAX_VOTERS = 500;

    /// @notice Maximum number of addresses in a batch registration
    uint public constant MAX_BATCH_SIZE = 100;

    /// @notice Minimum length required for a proposal description
    uint public constant MIN_DESCRIPTION_LENGTH = 10;

    /// @notice Maximum length allowed for a proposal description
    uint public constant MAX_DESCRIPTION_LENGTH = 500;

    /// @notice Represents the different stages of a voting session workflow
    /// @dev Each session progresses through these states sequentially
    enum WorkflowStatus {
        RegisteringVoters,              // Initial state: voters can be registered
        ProposalsRegistrationStarted,   // Voters can submit proposals
        ProposalsRegistrationEnded,     // Proposal submission is closed
        VotingSessionStarted,           // Voters can cast their votes
        VotingSessionEnded,             // Voting is closed
        VotesTallied                    // Votes have been counted, winner determined
    }

    /// @notice Represents a voter in the voting system
    /// @dev Stored in a mapping within each VotingSession
    struct Voter {
        bool isRegistered;      // Whether the voter is registered for this session
        bool hasVoted;          // Whether the voter has already cast a vote
        uint voteProposalId;    // The ID of the proposal the voter voted for
    }

    /// @notice Represents a proposal that can be voted on
    struct Proposal {
        string description;     // The description/content of the proposal
        uint voteCount;         // The number of votes received
    }

    /// @notice Represents a complete voting session with all its data
    /// @dev Contains nested mappings which prevent it from being returned directly
    struct VotingSession {
        uint id;                            // Unique identifier for this session
        uint parentSessionId;               // ID of parent session (if created from tie-break)
        uint childSessionId;                // ID of child session (if tie occurred)
        bool exists;                        // Whether this session has been created
        bool isCancelled;                   // Whether this session has been cancelled
        uint highestVoteCount;              // The highest vote count among proposals
        uint winningProposalId;             // The ID of the winning proposal
        bool hasWinner;                     // Whether a winner has been determined
        WorkflowStatus workflowStatus;      // Current state of the voting workflow
        Proposal[] proposals;               // Array of all proposals
        mapping(address => Voter) voters;   // Mapping of voter addresses to Voter data
        address[] voterAddresses;           // Array of registered voter addresses
    }

    /// @notice Mapping of session IDs to VotingSession data
    mapping(uint => VotingSession) votingSessions;

    /// @notice Counter for generating unique voting session IDs
    uint votingSessionIdCounter;

    // ==================== Events ====================

    /// @notice Emitted when a new voting session is created
    /// @param votingSessionId The ID of the newly created session
    event NewVotingSession(uint indexed votingSessionId);

    /// @notice Emitted when a voter is registered for a session
    /// @param votingSessionId The ID of the voting session
    /// @param voterAddress The address of the registered voter
    event VoterRegistered(uint indexed votingSessionId, address indexed voterAddress);

    /// @notice Emitted when the workflow status of a session changes
    /// @param votingSessionId The ID of the voting session
    /// @param previousStatus The previous workflow status
    /// @param newStatus The new workflow status
    event WorkflowStatusChange(uint indexed votingSessionId, WorkflowStatus previousStatus, WorkflowStatus newStatus);

    /// @notice Emitted when a new proposal is registered
    /// @param votingSessionId The ID of the voting session
    /// @param proposalId The ID of the registered proposal
    /// @param submitter The address of the voter who submitted the proposal
    event ProposalRegistered(uint indexed votingSessionId, uint proposalId, address indexed submitter);

    /// @notice Emitted when a voter casts a vote
    /// @param votingSessionId The ID of the voting session
    /// @param voter The address of the voter
    /// @param proposalId The ID of the proposal voted for
    event Voted(uint indexed votingSessionId, address indexed voter, uint proposalId);

    /// @notice Emitted when a winning proposal is determined
    /// @param votingSessionId The ID of the voting session
    /// @param proposalId The ID of the winning proposal
    event WinningProposition(uint indexed votingSessionId, uint proposalId);

    /// @notice Emitted when a new session is created due to a tie
    /// @param parentSessionId The ID of the parent session that had a tie
    /// @param votingSessionId The ID of the newly created tie-break session
    event RenewSession(uint indexed parentSessionId, uint indexed votingSessionId);

    /// @notice Emitted when a voting session is cancelled
    /// @param votingSessionId The ID of the cancelled session
    event SessionCancelled(uint indexed votingSessionId);

    /// @notice Emitted when multiple voters are registered in batch
    /// @param votingSessionId The ID of the voting session
    /// @param count The number of voters successfully registered
    event VotersRegisteredBatch(uint indexed votingSessionId, uint count);

    // ==================== Custom Errors ====================

    /// @notice Thrown when trying to access a non-existent voting session
    /// @param _votingSessionId The ID of the non-existent session
    error VotingSessionDoesNotExist(uint _votingSessionId);

    /// @notice Thrown when trying to register voters outside the registration phase
    error VoterRegistrationHasNotStarted();

    /// @notice Thrown when a non-registered voter tries to perform an action
    /// @param _address The address of the non-registered voter
    error VoterIsNotRegistered(address _address);

    /// @notice Thrown when trying to submit proposals outside the proposal phase
    error ProposalRegistrationHasNotStarted();

    /// @notice Thrown when trying to end proposal registration with no proposals
    error NoProposalsHasBeenRegistered();

    /// @notice Thrown when trying to start voting before proposal registration ended
    error ProposalRegistrationHasNotEnded();

    /// @notice Thrown when trying to access a non-existent proposal
    /// @param _proposalId The ID of the non-existent proposal
    error ProposalDoesNotExist(uint _proposalId);

    /// @notice Thrown when trying to vote outside the voting phase
    error VotingHasNotStarted();

    /// @notice Thrown when a voter tries to vote twice
    /// @param _address The address of the voter who already voted
    error UserHasAlreadyVoted(address _address);

    /// @notice Thrown when trying to end voting with no votes cast
    error NoVotesHasBeenRegistered();

    /// @notice Thrown when trying to tally votes before voting ended
    error VotingHasNotEnded();

    /// @notice Thrown when trying to get the winner before votes are tallied
    error VotingSessionHasNoWinner();

    /// @notice Thrown when the maximum number of proposals is reached
    error MaxProposalsReached();

    /// @notice Thrown when the maximum number of voters is reached
    error MaxVotersReached();

    /// @notice Thrown when a proposal description is too short
    /// @param minLength The minimum required length
    error DescriptionTooShort(uint minLength);

    /// @notice Thrown when a proposal description is too long
    /// @param maxLength The maximum allowed length
    error DescriptionTooLong(uint maxLength);

    /// @notice Thrown when trying to register an already registered voter
    /// @param _address The address of the already registered voter
    error VoterAlreadyRegistered(address _address);

    /// @notice Thrown when trying to register the zero address
    error InvalidAddress();

    /// @notice Thrown when trying to perform actions on a cancelled session
    error SessionAlreadyCancelled();

    /// @notice Thrown when trying to start proposals without any registered voters
    error NoVotersRegistered();

    /// @notice Thrown when trying to cancel a completed session
    error CannotCancelCompletedSession();

    /// @notice Thrown when batch size exceeds the maximum allowed
    /// @param maxSize The maximum allowed batch size
    error BatchSizeTooLarge(uint maxSize);

    // ==================== Constructor ====================

    /// @notice Initializes the contract and sets the deployer as owner
    constructor() Ownable(msg.sender) {}

    // ==================== External Functions ====================

    /// @notice Creates a new voting session
    /// @dev Only callable by the owner when the contract is not paused
    /// @dev Emits a NewVotingSession event
    function createVotingSession() external onlyOwner whenNotPaused {
        VotingSession storage newVotingSession = votingSessions[votingSessionIdCounter];
        newVotingSession.id = votingSessionIdCounter;
        newVotingSession.exists = true;
        emit NewVotingSession(votingSessionIdCounter);
        votingSessionIdCounter++;
    }

    // ==================== Internal Functions ====================

    /// @notice Creates a new session when there is a tie in the parent session
    /// @dev Copies tied proposals and all voters from parent session
    /// @dev The new session starts directly in VotingSessionStarted status
    /// @param _parentSessionId The ID of the parent session that had a tie
    /// @param _bestProposals Array of proposals that tied for the highest vote count
    function renewSession(uint _parentSessionId, Proposal[] memory _bestProposals) internal {
        VotingSession storage parentSession = votingSessions[_parentSessionId];
        VotingSession storage newVotingSession = votingSessions[votingSessionIdCounter];
        newVotingSession.id = votingSessionIdCounter;
        newVotingSession.parentSessionId = _parentSessionId;
        newVotingSession.exists = true;

        // Copy proposals with voteCount reset to 0
        for (uint i = 0; i < _bestProposals.length; i++) {
            newVotingSession.proposals.push(Proposal(_bestProposals[i].description, 0));
        }

        // Copy voters from parent session (without their vote)
        for (uint i = 0; i < parentSession.voterAddresses.length; i++) {
            address voterAddr = parentSession.voterAddresses[i];
            newVotingSession.voters[voterAddr].isRegistered = true;
            newVotingSession.voterAddresses.push(voterAddr);
        }

        // Mark parent session as completed (tie)
        parentSession.workflowStatus = WorkflowStatus.VotesTallied;
        parentSession.childSessionId = votingSessionIdCounter;
        emit WorkflowStatusChange(_parentSessionId, WorkflowStatus.VotingSessionEnded, WorkflowStatus.VotesTallied);

        // Start voting phase directly (proposals are already set)
        newVotingSession.workflowStatus = WorkflowStatus.VotingSessionStarted;

        emit NewVotingSession(votingSessionIdCounter);
        emit RenewSession(_parentSessionId, votingSessionIdCounter);
        emit WorkflowStatusChange(votingSessionIdCounter, WorkflowStatus.RegisteringVoters, WorkflowStatus.VotingSessionStarted);
        votingSessionIdCounter++;
    }

    // ==================== Voter Registration ====================

    /// @notice Registers a single voter for a voting session
    /// @dev Only callable by owner during RegisteringVoters phase
    /// @param _votingSessionId The ID of the voting session
    /// @param _address The address of the voter to register
    function registerVoter(uint _votingSessionId, address _address) external onlyOwner whenNotPaused {
        if (_address == address(0)) revert InvalidAddress();
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (currentVotingSession.isCancelled) revert SessionAlreadyCancelled();
        if (currentVotingSession.workflowStatus != WorkflowStatus.RegisteringVoters) revert VoterRegistrationHasNotStarted();
        if (currentVotingSession.voterAddresses.length >= MAX_VOTERS) revert MaxVotersReached();
        Voter storage voter = currentVotingSession.voters[_address];
        if (voter.isRegistered) revert VoterAlreadyRegistered(_address);
        voter.isRegistered = true;
        currentVotingSession.voterAddresses.push(_address);
        emit VoterRegistered(_votingSessionId, _address);
    }

    /// @notice Registers multiple voters in a single transaction
    /// @dev Only callable by owner during RegisteringVoters phase
    /// @dev Skips zero addresses and already registered voters silently
    /// @param _votingSessionId The ID of the voting session
    /// @param _addresses Array of voter addresses to register
    function registerVotersBatch(uint _votingSessionId, address[] calldata _addresses) external onlyOwner whenNotPaused {
        if (_addresses.length > MAX_BATCH_SIZE) revert BatchSizeTooLarge(MAX_BATCH_SIZE);
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (currentVotingSession.isCancelled) revert SessionAlreadyCancelled();
        if (currentVotingSession.workflowStatus != WorkflowStatus.RegisteringVoters) revert VoterRegistrationHasNotStarted();

        uint count = 0;
        for (uint i = 0; i < _addresses.length; i++) {
            if (currentVotingSession.voterAddresses.length >= MAX_VOTERS) revert MaxVotersReached();
            address addr = _addresses[i];
            if (addr != address(0) && !currentVotingSession.voters[addr].isRegistered) {
                currentVotingSession.voters[addr].isRegistered = true;
                currentVotingSession.voterAddresses.push(addr);
                count++;
            }
        }
        emit VotersRegisteredBatch(_votingSessionId, count);
    }

    // ==================== Proposal Management ====================

    /// @notice Starts the proposal registration phase for a voting session
    /// @dev Only callable by owner, requires at least one registered voter
    /// @dev Transitions from RegisteringVoters to ProposalsRegistrationStarted
    /// @param _votingSessionId The ID of the voting session
    function startProposalsRegistration(uint _votingSessionId) external onlyOwner whenNotPaused {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (currentVotingSession.isCancelled) revert SessionAlreadyCancelled();
        if (currentVotingSession.workflowStatus != WorkflowStatus.RegisteringVoters) revert VoterRegistrationHasNotStarted();
        if (currentVotingSession.voterAddresses.length == 0) revert NoVotersRegistered();
        currentVotingSession.workflowStatus = WorkflowStatus.ProposalsRegistrationStarted;
        emit WorkflowStatusChange(_votingSessionId, WorkflowStatus.RegisteringVoters, WorkflowStatus.ProposalsRegistrationStarted);
    }

    /// @notice Submits a new proposal to a voting session
    /// @dev Only callable by registered voters during proposal registration phase
    /// @dev Description must be between MIN_DESCRIPTION_LENGTH and MAX_DESCRIPTION_LENGTH characters
    /// @param _votingSessionId The ID of the voting session
    /// @param _description The description of the proposal
    function sendNewProposition(uint _votingSessionId, string calldata _description) external whenNotPaused {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (currentVotingSession.isCancelled) revert SessionAlreadyCancelled();
        if (currentVotingSession.workflowStatus != WorkflowStatus.ProposalsRegistrationStarted) revert ProposalRegistrationHasNotStarted();
        if (!currentVotingSession.voters[msg.sender].isRegistered) revert VoterIsNotRegistered(msg.sender);
        uint descLength = bytes(_description).length;
        if (descLength < MIN_DESCRIPTION_LENGTH) revert DescriptionTooShort(MIN_DESCRIPTION_LENGTH);
        if (descLength > MAX_DESCRIPTION_LENGTH) revert DescriptionTooLong(MAX_DESCRIPTION_LENGTH);
        if (currentVotingSession.proposals.length >= MAX_PROPOSALS) revert MaxProposalsReached();
        currentVotingSession.proposals.push(Proposal(_description, 0));
        emit ProposalRegistered(_votingSessionId, currentVotingSession.proposals.length - 1, msg.sender);
    }

    /// @notice Ends the proposal registration phase for a voting session
    /// @dev Only callable by owner, requires at least one proposal
    /// @dev Transitions from ProposalsRegistrationStarted to ProposalsRegistrationEnded
    /// @param _votingSessionId The ID of the voting session
    function endProposalsRegistration(uint _votingSessionId) external onlyOwner whenNotPaused {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (currentVotingSession.isCancelled) revert SessionAlreadyCancelled();
        if (currentVotingSession.workflowStatus != WorkflowStatus.ProposalsRegistrationStarted) revert ProposalRegistrationHasNotStarted();
        if (currentVotingSession.proposals.length == 0) revert NoProposalsHasBeenRegistered();
        currentVotingSession.workflowStatus = WorkflowStatus.ProposalsRegistrationEnded;
        emit WorkflowStatusChange(_votingSessionId, WorkflowStatus.ProposalsRegistrationStarted, WorkflowStatus.ProposalsRegistrationEnded);
    }

    // ==================== Voting ====================

    /// @notice Starts the voting phase for a voting session
    /// @dev Only callable by owner after proposal registration has ended
    /// @dev Transitions from ProposalsRegistrationEnded to VotingSessionStarted
    /// @param _votingSessionId The ID of the voting session
    function startVotingSession(uint _votingSessionId) external onlyOwner whenNotPaused {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (currentVotingSession.isCancelled) revert SessionAlreadyCancelled();
        if (currentVotingSession.workflowStatus != WorkflowStatus.ProposalsRegistrationEnded) revert ProposalRegistrationHasNotEnded();
        currentVotingSession.workflowStatus = WorkflowStatus.VotingSessionStarted;
        emit WorkflowStatusChange(_votingSessionId, WorkflowStatus.ProposalsRegistrationEnded, WorkflowStatus.VotingSessionStarted);
    }

    /// @notice Casts a vote for a proposal
    /// @dev Only callable by registered voters during voting phase
    /// @dev Each voter can only vote once per session
    /// @param _votingSessionId The ID of the voting session
    /// @param _proposalId The ID of the proposal to vote for
    function sendVote(uint _votingSessionId, uint _proposalId) external whenNotPaused {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (currentVotingSession.isCancelled) revert SessionAlreadyCancelled();
        if (_proposalId >= currentVotingSession.proposals.length) revert ProposalDoesNotExist(_proposalId);
        if (currentVotingSession.workflowStatus != WorkflowStatus.VotingSessionStarted) revert VotingHasNotStarted();
        Voter storage voter = currentVotingSession.voters[msg.sender];
        if (!voter.isRegistered) revert VoterIsNotRegistered(msg.sender);
        if (voter.hasVoted) revert UserHasAlreadyVoted(msg.sender);
        Proposal storage proposal = currentVotingSession.proposals[_proposalId];
        proposal.voteCount++;
        voter.hasVoted = true;
        voter.voteProposalId = _proposalId;
        if (proposal.voteCount > currentVotingSession.highestVoteCount) {
            currentVotingSession.highestVoteCount = proposal.voteCount;
        }
        emit Voted(_votingSessionId,msg.sender, _proposalId);
    }

    /// @notice Ends the voting phase for a voting session
    /// @dev Only callable by owner, requires at least one vote cast
    /// @dev Transitions from VotingSessionStarted to VotingSessionEnded
    /// @param _votingSessionId The ID of the voting session
    function endVotingSession(uint _votingSessionId) external onlyOwner whenNotPaused {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (currentVotingSession.isCancelled) revert SessionAlreadyCancelled();
        if (currentVotingSession.workflowStatus != WorkflowStatus.VotingSessionStarted) revert VotingHasNotStarted();
        if (currentVotingSession.highestVoteCount == 0) revert NoVotesHasBeenRegistered();
        currentVotingSession.workflowStatus = WorkflowStatus.VotingSessionEnded;
        emit WorkflowStatusChange(_votingSessionId, WorkflowStatus.VotingSessionStarted, WorkflowStatus.VotingSessionEnded);
    }

    /// @notice Computes the most voted proposal and determines the winner
    /// @dev If there is a tie, creates a new session with tied proposals via renewSession
    /// @dev Only callable by owner after voting has ended
    /// @param _votingSessionId The ID of the voting session
    function computeMostVotedProposal(uint _votingSessionId) external onlyOwner whenNotPaused {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (currentVotingSession.isCancelled) revert SessionAlreadyCancelled();
        if (currentVotingSession.workflowStatus != WorkflowStatus.VotingSessionEnded) revert VotingHasNotEnded();

        Proposal[] storage proposals = currentVotingSession.proposals;
        uint numberOfBestProposal;

        for (uint i = 0; i < proposals.length; i++) {
            if (proposals[i].voteCount == currentVotingSession.highestVoteCount) {
                numberOfBestProposal++;
            }
        }

        if (numberOfBestProposal == 1) {
            for (uint i = 0; i < proposals.length; i++) {
                if (proposals[i].voteCount == currentVotingSession.highestVoteCount) {
                    currentVotingSession.winningProposalId = i;
                    emit WinningProposition(_votingSessionId, i);
                    break;
                }
            }
            currentVotingSession.hasWinner = true;
            currentVotingSession.workflowStatus = WorkflowStatus.VotesTallied;
            emit WorkflowStatusChange(_votingSessionId, WorkflowStatus.VotingSessionEnded, WorkflowStatus.VotesTallied);
            return;
        }

        Proposal[] memory bestProposals = new Proposal[](numberOfBestProposal);
        uint index;
        for (uint i = 0; i < proposals.length; i++) {
            if (proposals[i].voteCount == currentVotingSession.highestVoteCount) {
                bestProposals[index] = proposals[i];
                index++;
            }
        }
        renewSession(currentVotingSession.id, bestProposals);
    }

    // ==================== View Functions ====================

    /// @notice Returns the winning proposal of a voting session
    /// @dev Only callable after votes have been tallied and a winner determined
    /// @param _votingSessionId The ID of the voting session
    /// @return The winning Proposal struct
    function getMostVotedProposal(uint _votingSessionId) external view returns(Proposal memory) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (!currentVotingSession.hasWinner) revert VotingSessionHasNoWinner();
        return currentVotingSession.proposals[currentVotingSession.winningProposalId];
    }

    /// @notice Returns the parent session ID for a tie-break session
    /// @dev Returns 0 if this is not a tie-break session
    /// @param _votingSessionId The ID of the voting session
    /// @return The parent session ID
    function getParentVotingSessionId(uint _votingSessionId) external view returns(uint) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        return votingSessions[_votingSessionId].parentSessionId;
    }

    /// @notice Returns the child session ID created from a tie-break
    /// @dev Returns 0 if no tie occurred
    /// @param _votingSessionId The ID of the voting session
    /// @return The child session ID
    function getChildVotingSessionId(uint _votingSessionId) external view returns(uint) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        return votingSessions[_votingSessionId].childSessionId;
    }

    /// @notice Returns all proposals for a voting session
    /// @param _votingSessionId The ID of the voting session
    /// @return Array of all Proposal structs
    function getAllProposals(uint _votingSessionId) external view returns(Proposal[] memory) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        return currentVotingSession.proposals;
    }

    /// @notice Returns a specific proposal by its ID
    /// @param _votingSessionId The ID of the voting session
    /// @param _proposalId The ID of the proposal
    /// @return The Proposal struct
    function getProposalById(uint _votingSessionId, uint _proposalId) external view returns(Proposal memory) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        if (_proposalId >= currentVotingSession.proposals.length) revert ProposalDoesNotExist(_proposalId);
        return currentVotingSession.proposals[_proposalId];
    }

    /// @notice Checks if an address is registered as a voter for a session
    /// @param _votingSessionId The ID of the voting session
    /// @param _address The address to check
    /// @return True if the address is registered, false otherwise
    function isRegistered(uint _votingSessionId, address _address) external view returns(bool) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        return currentVotingSession.voters[_address].isRegistered;
    }

    /// @notice Returns the current workflow status of a voting session
    /// @param _votingSessionId The ID of the voting session
    /// @return The current WorkflowStatus enum value
    function getWorkflowStatus(uint _votingSessionId) external view returns(WorkflowStatus) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage currentVotingSession = votingSessions[_votingSessionId];
        return currentVotingSession.workflowStatus;
    }

    /// @notice Returns all registered voter addresses for a session
    /// @param _votingSessionId The ID of the voting session
    /// @return Array of registered voter addresses
    function getVoterAddresses(uint _votingSessionId) external view returns(address[] memory) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        return votingSessions[_votingSessionId].voterAddresses;
    }

    /// @notice Returns the voting information for a specific voter
    /// @param _votingSessionId The ID of the voting session
    /// @param _voter The address of the voter to query
    /// @return registered Whether the voter is registered
    /// @return voted Whether the voter has voted
    /// @return votedProposalId The ID of the proposal the voter voted for
    function getVoterInfo(uint _votingSessionId, address _voter) external view returns(bool registered, bool voted, uint votedProposalId) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        Voter storage voter = votingSessions[_votingSessionId].voters[_voter];
        return (voter.isRegistered, voter.hasVoted, voter.voteProposalId);
    }

    /// @notice Returns comprehensive statistics for a voting session
    /// @param _votingSessionId The ID of the voting session
    /// @return proposalsCount The number of proposals submitted
    /// @return votersCount The number of registered voters
    /// @return highestVoteCount The highest vote count among proposals
    /// @return hasWinner Whether a winner has been determined
    /// @return winningProposalId The ID of the winning proposal (if any)
    /// @return isCancelled Whether the session has been cancelled
    /// @return workflowStatus The current workflow status
    /// @return parentSessionId The parent session ID (0 if none)
    /// @return childSessionId The child session ID (0 if none)
    function getSessionStats(uint _votingSessionId) external view returns(
        uint proposalsCount,
        uint votersCount,
        uint highestVoteCount,
        bool hasWinner,
        uint winningProposalId,
        bool isCancelled,
        WorkflowStatus workflowStatus,
        uint parentSessionId,
        uint childSessionId
    ) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage session = votingSessions[_votingSessionId];
        return (
            session.proposals.length,
            session.voterAddresses.length,
            session.highestVoteCount,
            session.hasWinner,
            session.winningProposalId,
            session.isCancelled,
            session.workflowStatus,
            session.parentSessionId,
            session.childSessionId
        );
    }

    /// @notice Returns the total number of voting sessions created
    /// @return The total count of voting sessions
    function getVotingSessionCount() external view returns(uint) {
        return votingSessionIdCounter;
    }

    /// @notice Checks if a voter has already cast their vote
    /// @param _votingSessionId The ID of the voting session
    /// @param _voter The address of the voter to check
    /// @return True if the voter has voted, false otherwise
    function hasVoted(uint _votingSessionId, address _voter) external view returns(bool) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        return votingSessions[_votingSessionId].voters[_voter].hasVoted;
    }

    // ==================== Admin Functions ====================

    /// @notice Pauses the contract, preventing most state-changing operations
    /// @dev Only callable by the owner
    /// @dev Use in case of emergency or security concerns
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract, resuming normal operations
    /// @dev Only callable by the owner
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Cancels a voting session
    /// @dev Cannot cancel a session that has already been completed (VotesTallied)
    /// @dev Once cancelled, no further actions can be performed on the session
    /// @param _votingSessionId The ID of the voting session to cancel
    function cancelSession(uint _votingSessionId) external onlyOwner whenNotPaused {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        VotingSession storage session = votingSessions[_votingSessionId];
        if (session.isCancelled) revert SessionAlreadyCancelled();
        if (session.workflowStatus == WorkflowStatus.VotesTallied) revert CannotCancelCompletedSession();
        session.isCancelled = true;
        emit SessionCancelled(_votingSessionId);
    }

    /// @notice Checks if a voting session has been cancelled
    /// @param _votingSessionId The ID of the voting session
    /// @return True if the session is cancelled, false otherwise
    function isSessionCancelled(uint _votingSessionId) external view returns(bool) {
        if (!votingSessions[_votingSessionId].exists) revert VotingSessionDoesNotExist(_votingSessionId);
        return votingSessions[_votingSessionId].isCancelled;
    }
}
