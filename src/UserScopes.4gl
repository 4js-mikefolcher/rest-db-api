PUBLIC CONSTANT cInsertOperation = "insert"
PUBLIC CONSTANT cUpdateOperation = "update"
PUBLIC CONSTANT cDeleteOperation = "delete"
PUBLIC CONSTANT cFetchOperation = "fetch"

PUBLIC TYPE TUserScopes RECORD
	scopeList DYNAMIC ARRAY OF STRING
END RECORD

PUBLIC FUNCTION (self TUserScopes) init(scopeString STRING) RETURNS ()

	CALL self.scopeList.clear()
	LET self.scopeList = scopeString.split("[,]")

END FUNCTION #init

PUBLIC FUNCTION (self TUserScopes) hasScope(scopeValue STRING) RETURNS BOOLEAN

	VAR idx = 0
	FOR idx = 1 TO self.scopeList.getLength()
		IF self.scopeList[idx].equalsIgnoreCase(scopeValue) THEN
			RETURN TRUE
		END IF
	END FOR

	RETURN FALSE

END FUNCTION #hasScope

PUBLIC FUNCTION (self TUserScopes) hasTableOperation(tabname STRING, operation STRING) RETURNS BOOLEAN

	VAR scopeValue = SFMT("Role.%1.%2", tabname, operation)
	RETURN self.hasScope(scopeValue)

END FUNCTION #hasTableOperation