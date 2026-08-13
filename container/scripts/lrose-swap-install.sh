# Bash script to find the two installations of LROSE (/usr/local/lrose) and
# (/share/lrose-nightly) in a user's $PATH and $LD_LIBRARY_PATH and swap them,
# giving priority to one or the other when running LROSE software
#
# Must be "source"ed when running in a terminal, or else this change will only
# occur in a subshell

unset LROSE_SHOW
LROSE_SHOW="false"
if [[ "$1" == "show" ]]
then
  LROSE_SHOW="true"
fi

LROSE_STABLE_PATH="/usr/local/lrose"
LROSE_NIGHTLY_PATH="/share/lrose-nightly"

lrose_swap_path() {
  declare -a SWAP_PATH=( $(echo "$1" | tr ":" " ") )

  # bash + grep sillyness
  declare -a STABLE_INDEX=( $(
    for ELEMENT in ${SWAP_PATH[@]}
    do
      echo $ELEMENT
    done | \
      grep -ne "$LROSE_STABLE_PATH" | \
      awk -F ":" '{print $1}'
    )
  )

  # bash + grep sillyness
  declare -a NIGHTLY_INDEX=( $(
    for ELEMENT in ${SWAP_PATH[@]}
    do
      echo $ELEMENT
    done | \
      grep -ne "$LROSE_NIGHTLY_PATH" | \
      awk -F ":" '{print $1}'
    )
  )

  STABLE_INDEX=$(( STABLE_INDEX[0] - 1 ))
  NIGHTLY_INDEX=$(( NIGHTLY_INDEX[0] - 1 ))

  # Min of the two indices
  CURRENT_INSTALL=$(( STABLE_INDEX < NIGHTLY_INDEX ? STABLE_INDEX : NIGHTLY_INDEX ))
  # Max of the two indices
  NEW_INSTALL=$(( STABLE_INDEX > NIGHTLY_INDEX ? STABLE_INDEX : NIGHTLY_INDEX ))

  echo "Current LROSE Installation: ${SWAP_PATH[$CURRENT_INSTALL]}" >&2

  # Don't swap if all we want to do is show the current install
  if [[ "$LROSE_SHOW" == "false" ]]
  then
    echo "Switching to ${SWAP_PATH[$NEW_INSTALL]}" >&2
    TMP="${SWAP_PATH[$CURRENT_INSTALL]}"
    SWAP_PATH[$CURRENT_INSTALL]=${SWAP_PATH[$NEW_INSTALL]}
    SWAP_PATH[$NEW_INSTALL]=$TMP
    echo ${SWAP_PATH[@]} | tr " " ":"
  else
    echo ""
  fi
}

# PATH
LROSE_TMP_PATH=$(lrose_swap_path "$PATH")
if [[ -n "$LROSE_TMP_PATH" ]]
then
  PATH=$LROSE_TMP_PATH
fi

# LD_LIBRARY_PATH
LROSE_TMP_PATH=$(lrose_swap_path "$LD_LIBRARY_PATH")
if [[ -n "$LROSE_TMP_PATH" ]]
then
  LD_LIBRARY_PATH=$LROSE_TMP_PATH
fi
