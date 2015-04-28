## raiser ##

**raiser** is a PL/SQL error manager.  **raiser** leverages the very feature rich functionality being developed as part of OraOpenSource's [logger](https://github.com/OraOpenSource/Logger "logger") utility through logger's plugin facility built into logger versions 3.0.0 and above.

**raiser** allows you to easily define and raise a specific exception (typically as some type of input/parameter validation), handle or log it as well as trace back to the line of code that threw it.  In addition, you are able to gain insights through metrics about the frequency of an exception in order to make changes in your application to better your user's experience.

**raiser** allows you to use error ranges outside the prescribed SQLCODE error ranges from Oracle (-20000 through -20999) - *you can use any positive integer*.  In order to have your error code returned to a calling application, your chosen error number is embedded in the PL/SQL error message (SQLERRM) as the PL/SQL exception datatype does not allow you to send back anything other than a SQLCODE and "some message" (SQLERRM).  

For expected errors (validations), the format of the message returned the caller when issued through raiser will always have:

 - SQLCODE = -20763
 - SQLERRM = "|logID:1234|errID:5678|you put in bad data, please don't do that"

As you can see, the SQLERRM error message has both the unique Logger ID from logger and your given Error ID.  Different calling apps (java, javascript, pl/sql, etc.) will be able to parse this message and display it properly to the user, i.e.

 - "*Error 5678, Dear User, you put in bad data, please don't do that.*"

If an unexpected exception occurs, the calling application will receive the same SQLCODE, however, this time the Oracle SQLCODE will be present in the "errID:" field with a negative integer 

 - SQLCODE = -20763
 - SQLERRM = "|logID:1234|errID:-1476|No Data Found"

In this case, the calling application can return an error message like "An unexpected error has occurred, the unique error message ID is 1234, please contact support referencing this ID."

Support teams can then work with development teams to determine the root cause of this exception by taking unique logger ID and looking up the call stack on the logger_logs table.

As noted above, **raiser** leverages logger, and as such you are able add all the same elements used in the logger.log_error procedure -- which means you are also able to capture any parameter values, scope and any additional context you may want to throw in there.

Some code samples of how to use raiser are:

