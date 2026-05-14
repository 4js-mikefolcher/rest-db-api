##############################################################################################
# custdemoService.4gl provides web service interface for all the tables in the
#  custdemo database
##############################################################################################

IMPORT com
IMPORT FGL com.fourjs.restdblib.ServiceHelper

MAIN
    DEFINE lMessage STRING
    CONNECT TO "northwind@localhost+driver='dbmpgs'" USER "nwuser" USING "fourjs123"

    CALL com.WebServiceEngine.RegisterRestService("com.fourjs.restdblib.ServiceHelper", "northwind")

    CALL startlog("NorthwindService.log")

    IF arg_val(1) == "--debug" THEN
        LET ServiceHelper.useScopes = FALSE
    END IF

    DISPLAY "Server started"
    LET lMessage = ServiceHelper.startService()
    DISPLAY lMessage

END MAIN