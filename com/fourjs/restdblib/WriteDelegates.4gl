##############################################################################################
# WriteDelegates.4gl
#
# Delegate-only write support for restdblib. The library does NOT contain generic
# INSERT/UPDATE/DELETE SQL; instead a service registers a callback FUNCTION per
# table (or a "*" fallback) for each operation, and the REST endpoints in
# ServiceHelper dispatch to it. This keeps "BDL as the gatekeeper": all write
# logic and access control live in customer-authored functions.
#
# A service registers callbacks at startup, e.g.:
#
#     IMPORT FGL com.fourjs.restdblib.WriteDelegates
#     IMPORT FGL MyHandlers
#     ...
#     CALL WriteDelegates.registerInsert("orders", FUNCTION MyHandlers.insertOrder)
#
# The registered function MUST match T_WriteHandler exactly, INCLUDING the
# parameter name "request" (parameter names are part of a Genero function
# signature), and must be a regular function (not a type method):
#
#     FUNCTION insertOrder(request WriteDelegates.T_WriteRequest)
#         RETURNS WriteDelegates.T_WriteResult
##############################################################################################
PACKAGE com.fourjs.restdblib

IMPORT util

PRIVATE CONSTANT _OP_INSERT = "insert"
PRIVATE CONSTANT _OP_UPDATE = "update"
PRIVATE CONSTANT _OP_DELETE = "delete"
PRIVATE CONSTANT _WILDCARD = "*"
PRIVATE CONSTANT _KEYPART_DELIM = "[,]"

# One component of a (possibly composite) key parsed from the request URL.
PUBLIC TYPE T_WriteKeyPart RECORD
    name STRING,             # key column name ("" for the unnamed single-key form)
    value STRING             # key value as received in the URL
END RECORD

# The write request handed to a delegate callback.
PUBLIC TYPE T_WriteRequest RECORD
    tableName STRING,                            # target table
    operation STRING,                            # "insert" | "update" | "delete"
    keyValue STRING,                             # raw {key} path segment (NULL for insert)
    keyParts DYNAMIC ARRAY OF T_WriteKeyPart,    # parsed single/composite key
    body util.JSONObject,                        # row values (insert/update); NULL for delete
    scopes STRING                                # caller scopes, for callback-level auth
END RECORD

# The result a delegate callback returns.
PUBLIC TYPE T_WriteResult RECORD
    ok BOOLEAN,                  # TRUE on success
    httpStatus INTEGER,          # success status to return (0 -> default 200)
    rowsAffected INTEGER,        # number of rows written
    body util.JSONObject,        # optional response payload (e.g. the inserted row)
    errorStatus INTEGER,         # on failure: HTTP status (400/403/404/409/500/501...)
    errorMessage STRING          # on failure: human-readable message
END RECORD

# A write delegate: receives the request, performs the write, returns a result.
PUBLIC TYPE T_WriteHandler FUNCTION(request T_WriteRequest) RETURNS T_WriteResult

# Per-operation registries keyed by table name (or "*").
PRIVATE DEFINE m_insert DICTIONARY OF T_WriteHandler
PRIVATE DEFINE m_update DICTIONARY OF T_WriteHandler
PRIVATE DEFINE m_delete DICTIONARY OF T_WriteHandler

##############################################################################################
# Registration
##############################################################################################

#+ Register the INSERT delegate for a table ("*" registers a fallback).
PUBLIC FUNCTION registerInsert(tableName STRING, handler T_WriteHandler)
    LET m_insert[tableName] = handler
END FUNCTION #registerInsert

#+ Register the UPDATE delegate for a table ("*" registers a fallback).
PUBLIC FUNCTION registerUpdate(tableName STRING, handler T_WriteHandler)
    LET m_update[tableName] = handler
END FUNCTION #registerUpdate

#+ Register the DELETE delegate for a table ("*" registers a fallback).
PUBLIC FUNCTION registerDelete(tableName STRING, handler T_WriteHandler)
    LET m_delete[tableName] = handler
END FUNCTION #registerDelete

#+ TRUE when a delegate (table-specific or "*") is registered for operation+table.
PUBLIC FUNCTION isRegistered(operation STRING, tableName STRING) RETURNS BOOLEAN
    DEFINE handler T_WriteHandler

    LET handler = resolve(operation, tableName)
    RETURN handler IS NOT NULL

END FUNCTION #isRegistered

##############################################################################################
# Dispatch
##############################################################################################

#+ Look up the delegate for operation+table and invoke it. Returns a 501 result
#+ when no delegate (table-specific or "*") is registered.
PUBLIC FUNCTION dispatch(operation STRING, request T_WriteRequest)
    RETURNS T_WriteResult
    DEFINE handler T_WriteHandler
    DEFINE result T_WriteResult

    LET handler = resolve(operation, request.tableName)
    IF handler IS NULL THEN
        RETURN errorResult(
            501,
            SFMT("No %1 handler registered for table '%2'",
                operation, request.tableName))
    END IF

    CALL handler(request) RETURNING result.*

    # Default the status of a result a callback returned without one.
    IF result.ok THEN
        IF result.httpStatus == 0 OR result.httpStatus IS NULL THEN
            LET result.httpStatus = 200
        END IF
    ELSE
        IF result.errorStatus == 0 OR result.errorStatus IS NULL THEN
            LET result.errorStatus = 500
        END IF
    END IF

    RETURN result

END FUNCTION #dispatch

#+ Resolve operation+table to a delegate: table-specific first, then the "*"
#+ fallback. Returns NULL when neither is registered.
PRIVATE FUNCTION resolve(operation STRING, tableName STRING)
    RETURNS T_WriteHandler
    DEFINE handler T_WriteHandler

    CASE operation
        WHEN _OP_INSERT
            LET handler = lookup(m_insert, tableName)
        WHEN _OP_UPDATE
            LET handler = lookup(m_update, tableName)
        WHEN _OP_DELETE
            LET handler = lookup(m_delete, tableName)
    END CASE

    RETURN handler

END FUNCTION #resolve

#+ Dictionary lookup with "*" fallback (no ELSE IF in BDL: nested IF in ELSE).
PRIVATE FUNCTION lookup(registry DICTIONARY OF T_WriteHandler, tableName STRING)
    RETURNS T_WriteHandler
    DEFINE handler T_WriteHandler

    IF registry.contains(tableName) THEN
        LET handler = registry[tableName]
    ELSE
        IF registry.contains(_WILDCARD) THEN
            LET handler = registry[_WILDCARD]
        END IF
    END IF

    RETURN handler

END FUNCTION #lookup

##############################################################################################
# Key parsing
##############################################################################################

#+ Parse a {key} path segment into one or more key parts.
#+   "5"                      -> [{name:"",         value:"5"}]
#+   "productid=5"            -> [{name:"productid",value:"5"}]
#+   "orderid=10248,productid=11"
#+                            -> [{orderid,10248},{productid,11}]
PUBLIC FUNCTION parseKeyParts(rawKey STRING)
    RETURNS DYNAMIC ARRAY OF T_WriteKeyPart
    DEFINE parts DYNAMIC ARRAY OF T_WriteKeyPart
    DEFINE tokens DYNAMIC ARRAY OF STRING
    DEFINE i, eqPos INTEGER
    DEFINE token STRING

    IF rawKey IS NULL THEN
        RETURN parts
    END IF

    LET tokens = rawKey.split(_KEYPART_DELIM)
    FOR i = 1 TO tokens.getLength()
        LET token = tokens[i].trimWhiteSpace()
        LET eqPos = token.getIndexOf("=", 1)
        IF eqPos > 0 THEN
            LET parts[i].name = token.subString(1, eqPos - 1).trimWhiteSpace()
            LET parts[i].value =
                token.subString(eqPos + 1, token.getLength()).trimWhiteSpace()
        ELSE
            LET parts[i].name = ""
            LET parts[i].value = token
        END IF
    END FOR

    RETURN parts

END FUNCTION #parseKeyParts

##############################################################################################
# Result helpers for callback authors
##############################################################################################

#+ A success result with an empty, ready-to-fill response body.
PUBLIC FUNCTION newResult() RETURNS T_WriteResult
    DEFINE result T_WriteResult
    LET result.ok = TRUE
    LET result.httpStatus = 200
    LET result.rowsAffected = 0
    LET result.body = util.JSONObject.create()
    RETURN result
END FUNCTION #newResult

#+ A success result carrying the rows affected and an optional response body.
PUBLIC FUNCTION okResult(rowsAffected INTEGER, body util.JSONObject)
    RETURNS T_WriteResult
    DEFINE result T_WriteResult
    LET result.ok = TRUE
    LET result.httpStatus = 200
    LET result.rowsAffected = rowsAffected
    LET result.body = body
    RETURN result
END FUNCTION #okResult

#+ A failure result carrying an HTTP status and message.
PUBLIC FUNCTION errorResult(httpStatus INTEGER, message STRING)
    RETURNS T_WriteResult
    DEFINE result T_WriteResult
    LET result.ok = FALSE
    LET result.errorStatus = httpStatus
    LET result.errorMessage = message
    RETURN result
END FUNCTION #errorResult
