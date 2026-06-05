# restdblib User Guide

How to use the **restdblib** package in your own Genero BDL application.

`restdblib` exposes relational data over a RESTful API. It provides ready-made,
database-agnostic **read** endpoints for any table, plus a **delegate-only**
write mechanism where you supply insert/update/delete logic as callback
functions. This guide covers consuming the published package; for building the
library itself from source see `README.md`.

- [1. Install](#1-install)
- [2. Import the package](#2-import-the-package)
- [3. A minimal service](#3-a-minimal-service)
- [4. Runtime requirements](#4-runtime-requirements)
- [5. Read endpoints](#5-read-endpoints)
- [6. Write endpoints (delegate-only)](#6-write-endpoints-delegate-only)
- [7. Authorization (scopes)](#7-authorization-scopes)
- [8. Error responses](#8-error-responses)
- [9. Gotchas](#9-gotchas)

---

## 1. Install

Add `restdblib` to your project with the Genero package manager:

```bash
fglpkg install restdblib
```

This records the dependency in your `fglpkg.json` and installs the compiled
package modules (`com/fourjs/restdblib/*.42m`). Then load the toolchain
environment so the runtime can resolve the installed package via `FGLLDPATH`:

```bash
eval "$(fglpkg env)"
```

`fglpkg env` adds the installed package locations to `FGLLDPATH`; no manual path
juggling is needed for the package modules.

---

## 2. Import the package

The package root is `com.fourjs.restdblib`. The two modules you use directly are:

| Import | What you call from it |
|--------|-----------------------|
| `com.fourjs.restdblib.ServiceHelper` | `registerService()`, `startService()`, and the `useScopes` flag. It also *defines* every REST endpoint (the engine invokes these). |
| `com.fourjs.restdblib.WriteDelegates` | `registerInsert/Update/Delete()`, the `T_WriteRequest` / `T_WriteResult` / `T_WriteHandler` types, and `okResult/errorResult` helpers. |

```4gl
IMPORT com
IMPORT FGL com.fourjs.restdblib.ServiceHelper
IMPORT FGL com.fourjs.restdblib.WriteDelegates   -- only if you expose writes
```

(`SQLHelper`, `UserScopes`, and `JsonParser` are internal; you normally do not
import them directly.)

---

## 3. A minimal service

A service is a normal Genero web service program. Four steps: connect, register
the REST resource, (optionally) register write delegates, run the loop.

```4gl
IMPORT com
IMPORT FGL com.fourjs.restdblib.ServiceHelper
IMPORT FGL com.fourjs.restdblib.WriteDelegates
IMPORT FGL MyWriteHandlers           -- your own callback module

MAIN
    DEFINE message STRING

    CONNECT TO "mydb@host+driver='dbmpgs'" USER "u" USING "p"

    CALL startlog("MyService.log")

    IF NOT ServiceHelper.registerService("myservice") THEN
        EXIT PROGRAM -1
    END IF

    -- Expose writes only for the tables you choose:
    CALL WriteDelegates.registerInsert("orders", FUNCTION MyWriteHandlers.insertOrder)
    CALL WriteDelegates.registerUpdate("orders", FUNCTION MyWriteHandlers.updateOrder)
    CALL WriteDelegates.registerDelete("orders", FUNCTION MyWriteHandlers.deleteOrder)

    IF arg_val(1) == "--debug" THEN
        LET ServiceHelper.useScopes = FALSE     -- bypass scope checks while developing
    END IF

    DISPLAY "Server started"
    LET message = ServiceHelper.startService()
    DISPLAY message
END MAIN
```

The name you pass to `registerService()` (e.g. `myservice`) is the first path
segment of every URL: `http://host:port/myservice/table/...`.

---

## 4. Runtime requirements

When you launch the service program:

| Variable | Requirement | Symptom if wrong |
|----------|-------------|------------------|
| `FGLAPPSERVER` | A **free TCP port** — the port the service listens on. | `bind function failed` / engine error -15504. |
| `LANG` / `LC_ALL` | A **UTF-8 locale** (e.g. `en_US.UTF-8`). | Multibyte rows fail to serialize; engine status **-32**. |

```bash
eval "$(fglpkg env)"
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 FGLAPPSERVER=8090 fglrun MyService.42m --debug
```

`startService()` runs a hardened request loop: per-request engine errors are
logged and the service keeps serving; only fatal engine codes stop it.

---

## 5. Read endpoints

Available for every table with no extra code (examples use service `myservice`):

| Method & path | Description |
|---------------|-------------|
| `GET /myservice/table/{table}` | All rows. |
| `GET /myservice/table/{table}/count` | Row count. |
| `GET /myservice/table/{table}/schema` | Column → Genero type map. |
| `GET /myservice/table/{table}/limit/{n}` | First `n` rows. |
| `GET /myservice/table/{table}/limit/{n}/offset/{o}` | Paging window. |
| `GET /myservice/table/{table}/query?column=&value=&operator=` | Filtered rows. |
| `POST /myservice/sql` | Run a query described by a JSON body. |

Filter operator tokens (the `operator` parameter):

| Token | SQL | | Token | SQL |
|-------|-----|-|-------|-----|
| `eq` | `=` | | `ge` | `>=` |
| `ne` | `<>` | | `le` | `<=` |
| `gt` | `>` | | `contains` | `LIKE %...%` |
| `lt` | `<` | | | |

Multiple AND-combined predicates use equal-length comma lists:

```
GET /myservice/table/products/query?column=categoryid,unitprice&value=1,15&operator=eq,gt
```

Values are bound using each column's real Genero type, so numeric/date filters
work on strictly typed databases too. Supply date values in the connection's
`DBDATE` format.

---

## 6. Write endpoints (delegate-only)

| Method & path | Operation |
|---------------|-----------|
| `POST /myservice/table/{table}` | Insert; JSON body = row values. |
| `PUT /myservice/table/{table}/{key}` | Update keyed row(s); JSON body = new values. |
| `DELETE /myservice/table/{table}/{key}` | Delete keyed row(s). |

A write is served **only** if you registered a delegate for that table+operation;
otherwise the endpoint returns **501 Not Implemented**. Register a `"*"` table to
provide a fallback handler for any other table.

### Key forms (single and composite)

The `{key}` path segment is parsed into one or more key parts:

| URL | Parsed `keyParts` |
|-----|-------------------|
| `/table/products/5` | `[{name:"", value:"5"}]` |
| `/table/products/productid=5` | `[{name:"productid", value:"5"}]` |
| `/table/order_details/orderid=10248,productid=11` | `[{orderid,10248},{productid,11}]` |

### The callback contract

A handler must match `WriteDelegates.T_WriteHandler` **exactly**, including the
parameter name `request` (parameter names are part of a Genero function
signature), and be a regular function (not a type method):

```4gl
PUBLIC TYPE T_WriteHandler FUNCTION(request T_WriteRequest) RETURNS T_WriteResult
```

`request` (`T_WriteRequest`) carries: `tableName`, `operation`
(`"insert"`/`"update"`/`"delete"`), the raw `keyValue`, the parsed `keyParts`
array, the JSON `body` (insert/update), and the caller's `scopes`.

Return a `T_WriteResult` built with a helper:

| Helper | Use |
|--------|-----|
| `WriteDelegates.okResult(rowsAffected, body)` | Success (`body` optional, may be NULL). |
| `WriteDelegates.errorResult(httpStatus, message)` | Failure with an HTTP status. |
| `WriteDelegates.newResult()` | Success with an empty, ready-to-fill body. |

### Example handler

```4gl
IMPORT util
IMPORT FGL com.fourjs.restdblib.WriteDelegates

PUBLIC FUNCTION updateOrder(request WriteDelegates.T_WriteRequest)
    RETURNS WriteDelegates.T_WriteResult
    DEFINE h base.SqlHandle
    DEFINE orderId, affected INTEGER

    LET orderId = request.keyParts[1].value
    TRY
        BEGIN WORK
        LET h = base.SqlHandle.create()
        CALL h.prepare("UPDATE orders SET shipcity = ? WHERE orderid = ?")
        CALL h.setParameter(1, request.body.get("shipcity"))
        CALL h.setParameter(2, orderId)
        CALL h.execute()
        LET affected = sqlca.sqlerrd[3]
        CALL h.close()
        COMMIT WORK
    CATCH
        RETURN WriteDelegates.errorResult(500, SFMT("Update failed: %1", sqlerrmessage))
    END TRY

    IF affected == 0 THEN
        RETURN WriteDelegates.errorResult(404, SFMT("No order %1", orderId))
    END IF
    RETURN WriteDelegates.okResult(affected, NULL)
END FUNCTION
```

The bundled example service ships complete single-key and composite-key handlers
(`categories`, `order_details`) you can copy from.

---

## 7. Authorization (scopes)

With `ServiceHelper.useScopes = TRUE` (default), each request's scopes (taken
from the `WSContext` `scopes` value, typically an access token) are checked
against `Role.<table>.<operation>`:

| Endpoint | Required scope |
|----------|----------------|
| Any read | `Role.<table>.fetch` |
| Insert (`POST`) | `Role.<table>.insert` |
| Update (`PUT`) | `Role.<table>.update` |
| Delete (`DELETE`) | `Role.<table>.delete` |

A missing scope returns **403**. Your write handler also gets `request.scopes`
for finer checks. Launch with `--debug` to set `useScopes = FALSE` while
developing.

---

## 8. Error responses

Errors come back as a JSON `responseError` object with an HTTP status:

| Status | Meaning |
|--------|---------|
| 400 | Bad request (e.g. query argument-count mismatch). |
| 403 | Caller lacks the required scope. |
| 404 | Table/row not found, or expected result was empty. |
| 500 | Internal/SQL error. |
| 501 | No write delegate registered for the table+operation. |

For writes, the status and message are whatever your delegate returned via
`errorResult()`.

---

## 9. Gotchas

When writing your delegate handlers:

- **Transactions.** On logged databases (e.g. PostgreSQL) wrap DML in
  `BEGIN WORK` / `COMMIT WORK`, with `ROLLBACK WORK` on error — the `WORK`
  keyword is required.
- **Typed string parameters.** Binding a string value to a typed column on a
  strict database can fail (`real > varchar`). Bind through a correctly typed
  FGL variable, or call `setParameterType()` before `setParameter()`.
- **`""` is NULL in BDL.** `x != ""` is NULL (falsy); test with `IS NOT NULL`
  or `.getLength() > 0`.
- **Function references match parameter names.** Your callback's parameter must
  be named `request` to match `T_WriteHandler`, and must be a regular function.
- **`INSERT ... RETURNING`** is not surfaced through `base.SqlHandle` on the
  `dbmpgs` driver; insert with `execute()`, then read the key separately
  (e.g. `SELECT lastval()`).
