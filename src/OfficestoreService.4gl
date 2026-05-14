##############################################################################################
# officestoreService.4gl provides web service interface for all the tables in the
#  officestore database
##############################################################################################
IMPORT com
IMPORT FGL com.fourjs.restdblib.ServiceHelper
IMPORT FGL OfficestoreCreate

MAIN
    DEFINE lMessage STRING

    CONNECT TO ":memory:+driver='dbmsqt'"
    CALL OfficestoreCreate.create_officestore_database()

    CALL com.WebServiceEngine.RegisterRestService(
        "ServiceHelper", "officestore")

    CALL startlog("officestoreService.log")

    IF arg_val(1) == "--debug" THEN
        LET ServiceHelper.useScopes = FALSE
    END IF

    DISPLAY "Server started"
    LET lMessage = ServiceHelper.startService()
    DISPLAY lMessage

END MAIN
