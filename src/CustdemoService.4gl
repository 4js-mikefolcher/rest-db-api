##############################################################################################
# custdemoService.4gl provides web service interface for all the tables in the
#  custdemo database
##############################################################################################

IMPORT com
IMPORT FGL ServiceHelper
IMPORT FGL CustdemoCreate

MAIN
    DEFINE lMessage STRING
    CONNECT TO ":memory:+driver='dbmsqt'"
    CALL CustdemoCreate.create_custdemo_database()

    CALL com.WebServiceEngine.RegisterRestService("ServiceHelper", "custdemo")

    CALL startlog("custdemoService.log")

    IF arg_val(1) == "--debug" THEN
        LET ServiceHelper.useScopes = FALSE
    END IF

    DISPLAY "Server started"
    LET lMessage = ServiceHelper.startService()
    DISPLAY lMessage

END MAIN
