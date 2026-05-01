#!/bin/bash

echo "=== Q Replication Configurations across ALL databases in this instance ==="
echo "Current running ASN processes (for reference):"
ps -ef | grep -E 'asnqcap|asnqapp' | grep -v grep
echo ""

# Load DB2 profile (IMPORTANT in scripts)
if [ -f ~/sqllib/db2profile ]; then
  . ~/sqllib/db2profile
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

  db2 -x <<EOF

CONNECT TO $DB;

-- Get schemas
WITH SCHEMAS AS (
  SELECT DISTINCT TABSCHEMA
  FROM SYSCAT.TABLES
  WHERE TABNAME IN ('IBMQREP_SENDQUEUES', 'IBMQREP_RECVQUEUES')
)
SELECT 'SCHEMA:' || TABSCHEMA FROM SCHEMAS;

-- APPLY (SENDQUEUES)
SELECT 'APPLY:' || APPLY_SERVER || ',' || APPLY_SCHEMA
FROM (
  SELECT DISTINCT APPLY_SERVER, APPLY_SCHEMA
  FROM SYSCAT.TABLES T, $DB.SYSCAT.TABLES S
  WHERE T.TABNAME='IBMQREP_SENDQUEUES'
  FETCH FIRST 1 ROW ONLY
) AS DUMMY
WHERE EXISTS (
  SELECT 1 FROM SYSCAT.TABLES 
  WHERE TABNAME='IBMQREP_SENDQUEUES'
);

-- CAPTURE (RECVQUEUES)
SELECT 'CAPTURE:' || CAPTURE_SERVER || ',' || CAPTURE_SCHEMA
FROM (
  SELECT DISTINCT CAPTURE_SERVER, CAPTURE_SCHEMA
  FROM SYSCAT.TABLES T, $DB.SYSCAT.TABLES S
  WHERE T.TABNAME='IBMQREP_RECVQUEUES'
  FETCH FIRST 1 ROW ONLY
) AS DUMMY
WHERE EXISTS (
  SELECT 1 FROM SYSCAT.TABLES 
  WHERE TABNAME='IBMQREP_RECVQUEUES'
);

CONNECT RESET;

EOF

done

echo ""
echo "=== Done. All Q Rep configs dumped. ==="
