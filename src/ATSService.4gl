##############################################################################################
# custdemoService.4gl provides web service interface for all the tables in the
#  custdemo database
##############################################################################################

IMPORT com
IMPORT FGL ServiceHelper

MAIN
    DEFINE lMessage STRING

    DATABASE fx

    CALL com.WebServiceEngine.RegisterRestService("ServiceHelper", "ats")

    CALL startlog("ATSService.log")

    DISPLAY "Server started"

    #Set useScopes to false to disable authorization
    LET ServiceHelper.useScopes = FALSE

    LET lMessage = ServiceHelper.startService()
    DISPLAY lMessage

END MAIN
