#!/bin/bash
# Q Replication Config Dumper
# Loops over ALL local (Indirect) databases in this DB2 instance
# and dumps every capture/apply server + schema configuration
# Also compares with running ASN processes

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

  # Find every schema that contains Q Rep control tables
  SCHEMAS=$(db2 -x "SELECT DISTINCT TABSCHEMA 
                    FROM SYSCAT.TABLES 
                    WHERE TABNAME IN ('IBMQREP_SENDQUEUES', 'IBMQREP_RECVQUEUES') 
                    ORDER BY TABSCHEMA" 2>/dev/null || echo "")

  if [ -z "$SCHEMAS" ]; then
    echo   No Q Replication control tables found.
    db2 terminate > /dev/null 2>&1
    continue
  fi

  for SCHEMA in $SCHEMAS; do
    echo   Q Rep schema: $SCHEMA

    # SENDQUEUES = Apply-side configuration
    if [ $(db2 -x "SELECT COUNT(*) FROM SYSCAT.TABLES 
                   WHERE TABSCHEMA='$SCHEMA' AND TABNAME='IBMQREP_SENDQUEUES'" 2>/dev/null | tr -d '[:space:]') -eq 1 ]; then
      echo     APPLY config IBMQREP_SENDQUEUES:
      db2 -x "SELECT DISTINCT APPLY_SERVER, APPLY_SCHEMA 
              FROM $SCHEMA.IBMQREP_SENDQUEUES;"
    fi

    # RECVQUEUES = Capture-side configuration
    if [ $(db2 -x "SELECT COUNT(*) FROM SYSCAT.TABLES 
                   WHERE TABSCHEMA='$SCHEMA' AND TABNAME='IBMQREP_RECVQUEUES'" 2>/dev/null | tr -d '[:space:]') -eq 1 ]; then
      echo     CAPTURE config IBMQREP_RECVQUEUES:
      db2 -x "SELECT DISTINCT CAPTURE_SERVER, CAPTURE_SCHEMA 
              FROM $SCHEMA.IBMQREP_RECVQUEUES;"
    fi
  done

  db2 terminate > /dev/null 2>&1
done

echo 
echo === Summary ===
echo ASN processes running: $(ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep | wc -l)
echo Review the dumped DB configs above against the running processes printed at the top.
echo Any server/schema pair in the ps output that does not appear in the DB dump is missing from the control tables gathered here 
echo typically because it lives in a database that was not accessible or has different control schemas.
echo === Done. All Q Rep configs dumped. ===
