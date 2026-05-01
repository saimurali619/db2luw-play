#!/bin/bash

echo "=== Q Replication Configurations across ALL databases in this instance ==="
echo ""

DB2PROFILE=~/sqllib/db2profile

if [ ! -f "$DB2PROFILE" ]; then
  echo "ERROR: db2profile not found at $DB2PROFILE"
  exit 1
fi

# Load DB list
. "$DB2PROFILE"
DBS=$(db2 list db directory | grep Indirect -B4 | grep name | awk '{print $NF}' | sort -u)

if [ -z "$DBS" ]; then
  echo "ERROR: No local databases found"
  exit 1
fi

echo "Found databases: $DBS"
echo ""

for DB in $DBS; do
  echo "--------------------------------------------------"
  echo "DATABASE: $DB"

  # ---- STEP 1: get schemas (fresh connect) ----
  . "$DB2PROFILE"
  db2 connect to "$DB" > /dev/null 2>&1

  if [ $? -ne 0 ]; then
    echo "  ❌ Cannot connect to $DB"
    continue
  fi

  SCHEMAS=$(db2 -x "
    SELECT DISTINCT RTRIM(TABSCHEMA)
    FROM SYSCAT.TABLES
    WHERE TABNAME IN ('IBMQREP_SENDQUEUES','IBMQREP_RECVQUEUES')
  ")

  db2 connect reset > /dev/null 2>&1

  if [ -z "$SCHEMAS" ]; then
    echo "  ❌ No Q Rep control tables found"
    continue
  fi

  echo "$SCHEMAS" | while read SCHEMA; do
    [ -z "$SCHEMA" ] && continue

    echo "  Q Rep schema: $SCHEMA"

    # ---- APPLY ----
    . "$DB2PROFILE"
    db2 connect to "$DB" > /dev/null 2>&1

    APPLY_COUNT=$(db2 -x "
      SELECT COUNT(*)
      FROM SYSCAT.TABLES
      WHERE TABSCHEMA='$SCHEMA'
        AND TABNAME='IBMQREP_SENDQUEUES'
    " | tr -d '[:space:]')

    db2 connect reset > /dev/null 2>&1

    if [ "$APPLY_COUNT" = "1" ]; then
      echo "    → APPLY config:"
      . "$DB2PROFILE"
      db2 connect to "$DB" > /dev/null 2>&1

      db2 -x "
        SELECT DISTINCT APPLY_SERVER, APPLY_SCHEMA
        FROM $SCHEMA.IBMQREP_SENDQUEUES
      "

      db2 connect reset > /dev/null 2>&1
    fi

    # ---- CAPTURE ----
    . "$DB2PROFILE"
    db2 connect to "$DB" > /dev/null 2>&1

    CAPTURE_COUNT=$(db2 -x "
      SELECT COUNT(*)
      FROM SYSCAT.TABLES
      WHERE TABSCHEMA='$SCHEMA'
        AND TABNAME='IBMQREP_RECVQUEUES'
    " | tr -d '[:space:]')

    db2 connect reset > /dev/null 2>&1

    if [ "$CAPTURE_COUNT" = "1" ]; then
      echo "    → CAPTURE config:"
      . "$DB2PROFILE"
      db2 connect to "$DB" > /dev/null 2>&1

      db2 -x "
        SELECT DISTINCT CAPTURE_SERVER, CAPTURE_SCHEMA
        FROM $SCHEMA.IBMQREP_RECVQUEUES
      "

      db2 connect reset > /dev/null 2>&1
    fi

  done

done

echo ""
echo "=== Done ==="
