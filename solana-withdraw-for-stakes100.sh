#!/bin/bash

### USAGE ###
# echo "export FEE_WALLET={FEE_ADDRESS}" | tee -a ~/.bashrc && source ~/.bashrc
# 
# curl -s https://gist.githubusercontent.com/legiojuve/b939cea133d79851d6a38498c9ca1d5c/raw/solana-withdraw-for-stakes100.sh | bash [-s -- --check]

### VARS ###

log_time_zone="Europe/Moscow"
log_file="/root/withdraw-log"

### FUNCTIONS ###

function log() {
        echo $(TZ=$log_time_zone date "+%Y-%m-%d %H:%M:%S") "${1}" | tee -a $log_file
}

function log_line() {
        echo "------------------------------------------------------------------------------------------" | tee -a $log_file
}
function log_empty() {
        echo "" | tee -a $log_file
}

function log_start() {
        echo "-------------------------------START AT $(TZ=$log_time_zone date "+%Y-%m-%d %H:%M:%S")-------------------------------" | tee -a $log_file
        echo "" | tee -a $log_file
}
function log_done() {
        echo "" | tee -a $log_file
        echo "--------------------------------DONE AT $(TZ=$log_time_zone date "+%Y-%m-%d %H:%M:%S")-------------------------------" | tee -a $log_file
}
function log_end() {
        echo "" | tee -a $log_file
        echo "--------------------------------END AT $(TZ=$log_time_zone date "+%Y-%m-%d %H:%M:%S")--------------------------------" | tee -a $log_file
}

### MAIN ###

URL="http://127.0.0.1:8899/"
BIN_FILE="/root/.local/share/solana/install/active_release/bin/solana"
#vote_account="9EeymqCPxrNQzUK8qfcMAMonytnQmK9bfEYoy7FyqpQ6"
#identity_account="7r5cfHQBg6Ly8kR3WfuA21vJwKrXfTMzSDU71UN95c8S"
vote_account="/root/solana/vote-account-keypair.json"
identity_account="/root/solana/validator-keypair.json"
re_numbers='^[0-9\.]+$'

MIN_VOTE_BALANCE=1
MIN_BALANCE=40
MIN_AVAILABLE_BALANCE=10

check_rewards=false

while [[ $# > 0 ]]; do
        case "$1" in
                --check)
                        check_rewards=true
                        shift 1
                ;;
                *)
                        log_exit "Unknown argument: $1"
                ;;
        esac
done

log_start

if ! $check_rewards; then
        if [[ -z "$FEE_WALLET" ]]; then
                log "ERROR! FEE address is empty"
                log_end
                exit 1
        fi

#        outResult=$(curl -s https://gist.githubusercontent.com/legiojuve/0633c9e531a3c358025497130c9b55d1/raw/binanceGetAssetDetail.sh | bash -s SOL 2>/dev/null)
#        if (($? == 0)) && [[ $outResult ]]; then
#                isError=$(echo $outResult | jq -r '.error')
#                if $isError; then
#                        log "ERROR! $(echo $outResult | jq -r '.result')"
#                        log_end
#                        exit 1
#                else
#                        depositStatus=$(echo $outResult | jq -r '.result.depositStatus')
#                        if $depositStatus; then
#                                log "SOL deposit status is TRUE on Binance"
#                                log_empty
#                        else
#                                log "STOP! SOL deposit status is FALSE on Binance"
#                                log_end
#                                exit 1
#                        fi
#                fi
#        else
#                log "ERROR! Cannot get accet (SOL) detail from Binance"
#                log_end
#                exit 1
#        fi
fi

#STAKES=$($BIN_FILE stakes $vote_account --url=$URL --output json 2>/dev/null)
STAKES=$($BIN_FILE stakes $vote_account --output json 2>/dev/null)
if (($? != 0)) || ! [[ $STAKES ]]; then
        log "ERROR or stakes are empty"
        log_end
        exit 1
fi

DELEGATORS_BASE64=$(curl --silent https://raw.githubusercontent.com/mr0wnage/gist/master/stakes_9EeymqCPxrNQzUK8qfcMAMonytnQmK9bfEYoy7FyqpQ6 | jq -r '@base64')
#DELEGATORS_BASE64=$(curl --silent https://gist.githubusercontent.com/legiojuve/a305a8466e43a8023778c4ba59f36be5/raw/stakes_9EeymqCPxrNQzUK8qfcMAMonytnQmK9bfEYoy7FyqpQ6 | jq -r '@base64')
if (($? != 0)) || ! [[ $DELEGATORS_BASE64 ]]; then
        log "ERROR or delegators are empty"
        log_end
        exit 1
fi

VOTE_BALANCE=$($BIN_FILE balance $vote_account --url=$URL 2>/dev/null | awk '{print $1}')
if (($? != 0)) || ! [[ $VOTE_BALANCE ]] || ! [[ $VOTE_BALANCE =~ $re_numbers ]]; then
        log "ERROR or Vote balance ($VOTE_BALANCE) not a number"
        log_end
        exit 1
fi

AVAILABLE_VOTE_BALANCE=$(echo "$VOTE_BALANCE-$MIN_VOTE_BALANCE" | bc -l)
if [[ $(bc -l <<< "$AVAILABLE_VOTE_BALANCE<=0") -eq 1 ]]; then
        log "Vote balance ($VOTE_BALANCE) too small. Minimum: $MIN_VOTE_BALANCE"
        log "STOP! Rewards are not withdraw from Vote account"
        AVAILABLE_VOTE_BALANCE=0
else
        if ! $check_rewards; then
                log "Vote balance: $VOTE_BALANCE"
                log "Let's withdraw ($AVAILABLE_VOTE_BALANCE) from Vote account..."
                outResult=$($BIN_FILE withdraw-from-vote-account $vote_account $identity_account $AVAILABLE_VOTE_BALANCE --authorized-withdrawer $vote_account --output=json --url=$URL 2>/dev/null)
                if (($? == 0)) && [[ $outResult ]]; then
                        signature=$(echo $outResult | jq -r '.signature')
                        if [[ $signature ]]; then
                                log "DONE! Rewards ($AVAILABLE_VOTE_BALANCE) have been withdrawn from Vote account"
                                log "{ \"signature\": \"$signature\" }" 
                                log "Waiting 10 sec..."
                                sleep 10
                        else
                                log "ERROR! Cannot withdraw rewards ($AVAILABLE_VOTE_BALANCE) from Vote account. No signature!"
                                log_end
                                exit 1
                        fi
                else
                        log "ERROR! Cannot withdraw rewards ($AVAILABLE_VOTE_BALANCE) from Vote account"
                        log_end
                        exit 1
                fi

                VOTE_BALANCE=$($BIN_FILE balance $vote_account --url=$URL 2>/dev/null | awk '{print $1}')
                if (($? != 0)) || ! [[ $VOTE_BALANCE ]] || ! [[ $VOTE_BALANCE =~ $re_numbers ]]; then
                        log "ERROR or NEW Vote balance ($VOTE_BALANCE) not a number"
                        log_end
                        exit 1
                fi
        fi
fi

BALANCE=$($BIN_FILE balance $identity_account --url=$URL 2>/dev/null | awk '{print $1}')
if (($? != 0)) || ! [[ $BALANCE ]] || ! [[ $BALANCE =~ $re_numbers ]]; then
        log "ERROR or NEW Identity balance ($BALANCE) not a number"
        log_end
        exit 1
fi

if $check_rewards; then
        NEW_VOTE_BALANCE=$(echo "$VOTE_BALANCE-$AVAILABLE_VOTE_BALANCE" | bc -l)
        NEW_BALANCE=$(echo "$BALANCE+$AVAILABLE_VOTE_BALANCE" | bc -l)
else
        NEW_VOTE_BALANCE=$VOTE_BALANCE
        NEW_BALANCE=$BALANCE
fi

log_empty
log_line
log "NEW Vote balance: $NEW_VOTE_BALANCE"
log "NEW Identity balance: $NEW_BALANCE"
log_empty
log_line

AVAILABLE_BALANCE=$(echo "$NEW_BALANCE-$MIN_BALANCE" | bc -l)
if [[ $(bc -l <<< "$AVAILABLE_BALANCE<$MIN_AVAILABLE_BALANCE") -eq 1 ]]; then
        log "Available Identity balance ($AVAILABLE_BALANCE) too small. Minimum: $MIN_AVAILABLE_BALANCE"
        if $check_rewards; then
                AVAILABLE_BALANCE=100
                log "CHECKING for $AVAILABLE_BALANCE"
        else
                log "STOP! Rewards are not withdraw from Identity account"
                log_end
                exit 1
        fi
fi

log "Available Identity balance: $AVAILABLE_BALANCE"

VALID_DELEGATORS=( ) # Array of valid delegators

TotalDelegated=0

for row in ${DELEGATORS_BASE64}; do

        _jq() {
                echo ${row} | base64 --decode | jq -r ${1}
        }

        name=$(_jq '.name')
        solWallet=$(_jq '.solWallet')

        fee=$(_jq '.fee')
        if (($? != 0)) || ! [[ $fee ]] || ! [[ $fee =~ $re_numbers ]] || [[ $(bc -l <<< "$fee>99") -eq 1 ]]; then
                fee="0"
        fi

        if [[ $name ]] && [[ $solWallet ]] && [[ $fee ]]; then
                TotalDelegatorStake=0

                delegator_stakes=$(_jq '.stakes[].stakePubkey')
                for stakePubkey in $delegator_stakes; do
                        CurrentDelegatedStake=$(echo $STAKES | jq -r --arg stakePubkey $stakePubkey '.[] | select(.stakePubkey == $stakePubkey) | .activeStake')
                        if (($? != 0)) || ! [[ $CurrentDelegatedStake ]] || ! [[ $CurrentDelegatedStake =~ $re_numbers ]]; then
                                log_empty
                                log "$name ($stakePubkey): ERROR or current delegator stake ($CurrentDelegatedStake) not a number"
                                log_end
                                exit 1
                        fi
                        if [[ $(bc -l <<< "$CurrentDelegatedStake>0") -eq 1 ]]; then
                                TotalDelegatorStake=$(echo "$TotalDelegatorStake+$CurrentDelegatedStake" | bc -l)
                        else
                                log_empty
                                log "$name ($stakePubkey): Current delegator stake ($CurrentDelegatedStake) less or equal 0"
                                log_end
                                exit 1
                        fi
                done

                if [[ $(bc -l <<< "$TotalDelegatorStake>0") -eq 1 ]]; then
                        TotalDelegated=$(echo "$TotalDelegated+$TotalDelegatorStake" | bc -l)
                        Delegator_Datas="{\"name\":\"$name\",\"solWallet\":\"$solWallet\",\"fee\":\"$fee\",\"stake\":$TotalDelegatorStake}"
                        VALID_DELEGATORS+=($Delegator_Datas)
                else
                        log_empty
                        log "$name: Total delegatar stake ($TotalDelegatorStake) less or equal 0"
                        log_end
                        exit 1
                fi
        fi

done

log "TOTAL DELEGATED: $(printf %.4f $(echo "$TotalDelegated/1000000000" | bc -l))"
log_empty

TotalPart=0
TotalReward=0
TotalFee=0

for Delegator_Datas in ${VALID_DELEGATORS[@]}; do
        _jq() {
                echo ${Delegator_Datas} | jq -r ${1}
        }
        name=$(_jq '.name')
        solWallet=$(_jq '.solWallet')
        stake=$(_jq '.stake')
        fee=$(_jq '.fee')
        part=$(echo "$stake/$TotalDelegated" | bc -l)

        reward_full=$(echo "$part*$AVAILABLE_BALANCE" | bc -l)
        reward_full8=$(printf %.8f $reward_full)

        reward_fee=$(echo "$reward_full8*$fee*0.01" | bc -l)
        reward_fee8=$(printf %.8f $reward_fee)

        reward8=$(printf %.8f $(echo "$reward_full8-$reward_fee8" | bc -l))

        TotalPart=$(echo "$TotalPart+$part" | bc -l)
        TotalReward=$(echo "$TotalReward+$reward8" | bc -l)
        TotalFee=$(echo "$TotalFee+$reward_fee8" | bc -l)

        log_line
        log "!!! $name: stake: $(printf %.4f $(echo "$stake/1000000000" | bc -l)); part: $(printf %.4f $(echo "$part*100" | bc -l))%"
        log "!!! $name: rewards: $reward_full8; fee: $fee% ($reward_fee8); send: $reward8"
        if ! $check_rewards; then
                log "!!! $name: Let's withdraw rewards ($reward8) to $solWallet"
                outResult=$($BIN_FILE transfer -k $identity_account $solWallet $reward8 --output=json --url=$URL 2>/dev/null)
                if (($? == 0)) && [[ $outResult ]]; then

                        signature=$(echo $outResult | jq -r '.signature')
                        if [[ $signature ]]; then
                                log "!!! $name: DONE! Rewards ($reward8) have been withdrawn to $solWallet"
                                log "{ \"signature\": \"$signature\" }" 
                                sleep 3
                        else
                                log "!!! $name: ERROR! Cannot withdraw rewards ($reward8) to $solWallet"
                        fi

                else
                        log "!!! $name: ERROR! Cannot withdraw rewards ($reward8) to $solWallet"
                fi
        fi

        log_empty
done

if [[ $(bc -l <<< "$TotalFee>0") -eq 1 ]] && ! $check_rewards; then
        log_line
        log "!!! FEE: Let's withdraw fee ($TotalFee) to $FEE_WALLET"
        outResult=$($BIN_FILE transfer -k $identity_account $FEE_WALLET $TotalFee --output=json --url=$URL 2>/dev/null)
        if (($? == 0)) && [[ $outResult ]]; then

                signature=$(echo $outResult | jq -r '.signature')
                if [[ $signature ]]; then
                        log "!!! FEE! Fee ($TotalFee) have been withdrawn to $FEE_WALLET"
                        log "{ \"signature\": \"$signature\" }" 
                        sleep 3
                else
                        log "!!! FEE: ERROR! Cannot withdraw fee ($TotalFee) to $FEE_WALLET"
                fi

        else
                log "!!! FEE: ERROR! Cannot withdraw fee ($TotalFee) to $FEE_WALLET"
        fi

        log_empty

fi

TotalSend=$(echo "$TotalReward+$TotalFee" | bc -l)
FeePart=$(echo "$TotalFee*100/$AVAILABLE_BALANCE" | bc -l)
FeePart2=$(printf %.2f $FeePart)

log_line
log "TOTAL PART: $(printf %.4f $(echo "$TotalPart*100" | bc -l))%"
log "TOTAL REWARDS: $(printf %.8f $TotalReward)"
log "TOTAL FEE: $(printf %.8f $TotalFee) ($FeePart2%)"
log "TOTAL SEND (REWARDS+FEE): $(printf %.8f $TotalSend)"
log_empty
log_line
BALANCE=$($BIN_FILE balance $identity_account --url=$URL 2>/dev/null | awk '{print $1}')
log "NEW Identity balance: $BALANCE"
log_done
