#!/bin/bash

echo "=== Q Replication Configurations across ALL databases in this instance ==="
echo "Current running ASN processes (for reference):"
ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep
echo ""

DB2PROFILE=~/sqllib/db2profile

# Ensure DB2 profile exists
if [ ! -f "$DB2PROFILE" ]; then
  echo "ERROR: db2profile not found at $DB2PROFILE"
  exit 1
fi

# Function: run SQL safely (connect + query + disconnect in ONE call)
run_db2_query() {
  DBNAME="$1"
  SQL="$2"

  . "$DB2PROFILE"

  OUTPUT=$(db2 -x "connect to $DBNAME; $SQL; connect reset;" 2>&1)

  # If any SQL error occurs, ignore output
  if echo "$OUTPUT" | grep -q "^SQL[0-9]"; then
    return 1
  fi

  # Clean output (remove blanks + trim spaces)
  echo "$OUTPUT" | sed '/^$/d' | sed 's/^[ \t]*//;s/[ \t]*$//'
}

# Get DB list (your original working logic)
. "$DB2PROFILE"
DBS=$(db2 list db directory | grep Indirect -B4 | grep name | awk '{print $NF}' | sort -u)

if [ -z "$DBS" ]; then
  echo "ERROR: No local databases found in DB directory."
  exit 1
fi

echo "Found local databases: $DBS"
echo ""

for DB in $DBS; do
  echo "--------------------------------------------------"
  echo "DATABASE: $DB"

  # Get schemas safely
  SCHEMAS=$(run_db2_query "$DB" "
    SELECT DISTINCT TABSCHEMA
    FROM SYSCAT.TABLES
    WHERE TABNAME IN ('IBMQREP_SENDQUEUES', 'IBMQREP_RECVQUEUES')
    ORDER BY TABSCHEMA
  ")

  if [ -z "$SCHEMAS" ]; then
    echo "  No Q Replication control tables found."
    continue
  fi

  echo "$SCHEMAS" | while IFS= read -r SCHEMA; do
    [ -z "$SCHEMA" ] && continue

    # Validate schema name (skip garbage like SQL1024N)
    if [[ ! "$SCHEMA" =~ ^[A-Z0-9_]+$ ]]; then
      continue
    fi

    echo "  Q Rep schema: $SCHEMA"

    # SENDQUEUES check
    SEND_COUNT=$(run_db2_query "$DB" "
      SELECT COUNT(*)
      FROM SYSCAT.TABLES
      WHERE TABSCHEMA='$SCHEMA'
        AND TABNAME='IBMQREP_SENDQUEUES'
    " | tr -d '[:space:]')

    if [ "$SEND_COUNT" = "1" ]; then
      echo "    → APPLY config (IBMQREP_SENDQUEUES):"
      run_db2_query "$DB" "
        SELECT DISTINCT APPLY_SERVER, APPLY_SCHEMA
        FROM $SCHEMA.IBMQREP_SENDQUEUES
      "
    fi

    # RECVQUEUES check
    RECV_COUNT=$(run_db2_query "$DB" "
      SELECT COUNT(*)
      FROM SYSCAT.TABLES
      WHERE TABSCHEMA='$SCHEMA'
        AND TABNAME='IBMQREP_RECVQUEUES'
    " | tr -d '[:space:]')

    if [ "$RECV_COUNT" = "1" ]; then
      echo "    → CAPTURE config (IBMQREP_RECVQUEUES):"
      run_db2_query "$DB" "
        SELECT DISTINCT CAPTURE_SERVER, CAPTURE_SCHEMA
        FROM $SCHEMA.IBMQREP_RECVQUEUES
      "
    fi

  done

done

echo ""
echo "=== Done. All Q Rep configs dumped. ==="
