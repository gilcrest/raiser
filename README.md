## raiser ##

**raiser** is a PL/SQL error manager.  **raiser** leverages the very feature rich functionality being developed as part of OraOpenSource's [logger](https://github.com/OraOpenSource/Logger "logger") utility through logger's plugin facility built into logger versions 3.0.0 and above.

**raiser** allows you to easily define and raise a specific exception (typically as some type of input/parameter validation), handle or log it as well as trace back to the line of code that threw it.  In addition, you are able to gain insights through metrics about the frequency of an exception in order to make changes in your application to better your user's experience.

**raiser** allows you to use error ranges outside the prescribed SQLCODE error ranges from Oracle (-20000 through -20999) - *you can use any integer*.  In order to have your error code returned to a calling application, your chosen error number is embedded in the PL/SQL error message (SQLERRM) as the PL/SQL exception datatype does not allow you to send back anything other than a SQLCODE and "some message" (SQLERRM).  The format of the message returned the caller when issued through raiser will always have:

 - SQLCODE = -20763
 - SQLERRM = "|1234|Your Super Helpful Error Message"

