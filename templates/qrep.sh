#!/bin/bash

echo "=== Q Replication Configurations across ALL databases in this instance ==="
echo "Current running ASN processes (for reference):"
ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep
echo ""

DB2PROFILE=~/sqllib/db2profile

# Function: run query with fresh environment + connect/disconnect
run_db2_query() {
  DBNAME="$1"
  SQL="$2"

  # Ensure DB2 environment is loaded EVERY time
  if [ -f "$DB2PROFILE" ]; then
    . "$DB2PROFILE"
  else
    echo "  ❌ db2profile not found at $DB2PROFILE"
    return 1
  fi

  db2 connect to "$DBNAME" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "  ❌ Connection failed for $DBNAME"
    return 1
  fi

  RESULT=$(db2 -x "$SQL" 2>/dev/null)

  db2 connect reset > /dev/null 2>&1

  echo "$RESULT"
}

# Get local databases (same logic you trust)
if [ -f "$DB2PROFILE" ]; then
  . "$DB2PROFILE"
fi

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

  # Get schemas
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

  for SCHEMA in $SCHEMAS; do
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
