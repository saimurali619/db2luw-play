```bash
#!/bin/bash
# Q Replication Config Dumper - Fixed with debug to see why no tables are found
# Loops over ALL local databases and shows exactly what the catalog query returns

echo === Q Replication Configurations across ALL databases in this instance ===
echo Current running ASN processes for reference:
ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep
echo Running ASN processes count: $(ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep | wc -l)
echo 

# Get list of all LOCAL (Indirect) databases
DBS=$(db2 list db directory | grep Indirect -B4 | grep name | awk '{print $NF}' | sort -u)

if [ -z "$DBS" ]; then
  echo ERROR: No local databases found in DB directory.
  exit 1
fi

echo Found local databases: $DBS
echo 

for DB in $DBS; do
  echo --------------------------------------------------
  echo DATABASE: $DB
  
  # Connect
  db2 connect to "$DB" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo   Failed to connect to $DB check permissions / instance
    continue
  fi

  # Quick connection test
  if ! db2 -x "VALUES 1" > /dev/null 2>&1; then
    echo   Connection test failed for $DB
    db2 terminate > /dev/null 2>&1
    continue
  fi

  echo DEBUG: Checking Q Rep control tables in database $DB

  # Raw query output so we can see exactly what is happening
  RAW=$(db2 -x "SELECT DISTINCT TABSCHEMA 
                FROM SYSCAT.TABLES 
                WHERE TABNAME IN ('IBMQREP_SENDQUEUES', 'IBMQREP_RECVQUEUES') 
                AND TABSCHEMA NOT LIKE 'SYS%' 
                ORDER BY TABSCHEMA" 2>&1)

  echo DEBUG Raw schema query output for $DB:
  echo "$RAW"
  echo 

  # Clean schemas from raw output
  SCHEMAS=$(echo "$RAW" | grep -E '^[A-Z][A-Z0-9_]+$' | sort -u || echo "")

  if [ -z "$SCHEMAS" ]; then
    echo   No Q Replication control tables found in this database.
    db2 terminate > /dev/null 2>&1
    continue
  fi

  for SCHEMA in $SCHEMAS; do
    echo   Q Rep schema: $SCHEMA

    # SENDQUEUES = Apply-side configuration
    SEND_COUNT=$(db2 -x "SELECT COUNT(*) FROM SYSCAT.TABLES 
                   WHERE TABSCHEMA='$SCHEMA' AND TABNAME='IBMQREP_SENDQUEUES'" 2>/dev/null | tr -d '[:space:]')
    if echo "$SEND_COUNT" | grep -q '^1$'; then
      echo     APPLY config IBMQREP_SENDQUEUES:
      db2 -x "SELECT DISTINCT APPLY_SERVER, APPLY_SCHEMA 
              FROM $SCHEMA.IBMQREP_SENDQUEUES;" 2>/dev/null
    fi

    # RECVQUEUES = Capture-side configuration
    RECV_COUNT=$(db2 -x "SELECT COUNT(*) FROM SYSCAT.TABLES 
                   WHERE TABSCHEMA='$SCHEMA' AND TABNAME='IBMQREP_RECVQUEUES'" 2>/dev/null | tr -d '[:space:]')
    if echo "$RECV_COUNT" | grep -q '^1$'; then
      echo     CAPTURE config IBMQREP_RECVQUEUES:
      db2 -x "SELECT DISTINCT CAPTURE_SERVER, CAPTURE_SCHEMA 
              FROM $SCHEMA.IBMQREP_RECVQUEUES;" 2>/dev/null
    fi
  done

  db2 terminate > /dev/null 2>&1
done

echo 
echo === Summary ===
echo ASN processes running: $(ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep | wc -l)
echo Review the dumped DB configs above against the running processes printed at the top.
echo Look at the DEBUG lines to see why tables were not found.
echo === Done. All Q Rep configs dumped. ===
```
