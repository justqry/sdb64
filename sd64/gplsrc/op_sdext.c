/* OP_SDEXT.C
*
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 * opcodes for ScarletDME extension function
 * 
 * START-HISTORY:
 * 06 Aug 2024 MAB add SDEXT
 * 08 Aug 2024 mab add embedded python
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * Opcodes:
 *    op_sdext    SDEXT   
 *    for basic function SDEXT(Function_id, IsArgMV, Arg)
 *    where:
 *    Function_Id = the integer value used to identify what c code / function is execute.
 *    IsArgMV     = If passing a multiple arguments in Arg, set to true, otherwise false.  
 *    Arg         = string value passed to the c code / function. For functions requiring multiple arguments, set IsArgMV to true 
 *                  and pass arguments in a FIELD_MARK separated string, with a maximum of 10 fields
 *
 * END-DESCRIPTION
 *
 
 * START-CODE
 */


#include <linux/limits.h>
#include <sodium.h>

#include "sd.h"
#include "keys.h"

extern char* sd_salt();
extern char* sd_KeyFromPW(char* mypassword, char* mysalt);

/* 20240808 mab embedding python? */
#ifdef EMBED_PYTHON
extern void sdext_py(int key, char* Arg);
#endif

char* SDMEArgArray[SD_MAX_ARGS];          /* create an array of pointers, for string arguments (for SDEXT call ) not sure if this is correct */
char* NullString(void); 

Private void sdme_err_rsp(int errnbr);

/* ======================================================================
   op_sdext()   op code for BASIC function  SDME.EXT   
   rtnval = SDEXT(Arg,IsArgMV,key)
   rem: code generated by BCOMP will be
   LDSLCL   RTNVAL    Load onto stack short local variable address for RTNVAL
   LDSLCL   ARG       Load onto stack short local variable address for ARG
   LDSLCL   ISARGMV   Load onto stack short local variable address for ISARGMV
   LDSINT   key       Load onto stack short integer
   SDEXT              (op code for op_sdme_ext here)
   STOR               Store onto stack return value in rtnval

      Stack:
        +=============================++=============================+
        +       STACK On Entry        ++       STACK On Exit         +
        +=============================++=============================+
estack> +    next available descr     ++    next available descr     +
        +=============================++=============================+
        +  descriptor w/ integer      ++  Addr to descr for RTNVAL   +
        +      key value              ++                             +
        +=============================++=============================+
        +  descriptor w/ integer      ++   
        +      IsArgMV                ++
        +=============================++
        + Addr to descriptor for Arg  ++   
        +=============================++
		
	   patterned from op_ospath() in op_dio2.c */

void op_sdext() {


  char myErrMsg[SD_ERR_MSG_LEN + 1];    /* hardcoded max string length is set to 512 char need to do something more "durable" */
  int32_t myval_len;
  int32_t mybuf_sz;
  char* myval_buffer;                      /* buffer for past value string  */
  STRING_CHUNK* str;
  int argIdx;
  int argCnt;
  int16_t key;
  int16_t IsArgMV;

  char* myFM = "\xFE";

  DESCRIPTOR* descr;
  
  /* set the process.status flag to  "successful"      */
  /* User can retrieve this status with the BASIC function STATUS()*/
    process.status = 0;

  /* Get action key */
  descr = e_stack - 1;   /* e_stack - 1 points to key descriptor */
  GetInt(descr);
  key = (int16_t)(descr->data.value);
  k_pop(1);   /* after pop() e_stack - 1 points to descr which holds ISArgMV  */

  /* Get IsArgMV Flag */
  descr = e_stack - 1;
  GetInt(descr);
  IsArgMV = (int16_t)(descr->data.value);
  k_pop(1);   /* * after pop() e_stack - 1 points to descr which holds ARG */

  /* Get val string */
  descr = e_stack - 1;
  k_get_string(descr);
  str = descr->data.str.saddr;
  /* is there something there? */
  if (str == NULL){
	  myval_len = 0;  
    mybuf_sz = 1;              /* room for string terminator */
  }else{
	 myval_len =  str->string_len;
     mybuf_sz  =  myval_len+1; /* room for string terminator */
  }
  
  /* allocate space for val string */
  myval_buffer = malloc(mybuf_sz * sizeof(char));
  if (myval_buffer == NULL){
   /* so here is a question, what to do if we cannot allocate memory?
	  We will end execution of program and attempt to report error  */
     k_error(sysmsg(10005));   /* Insufficient memory for buffer allocation */
	 /* We never come back from k_error */
  }

  /* move the passed argument string to our buffer */
  if (myval_len == 0){
	  myval_buffer[0] = '\0';
  } else {
   /* rem string length returned by k_get_c_string excludes terminator in count!*/ 
      myval_len = k_get_c_string(descr, myval_buffer, myval_len);
  }
  
  k_dismiss();   /* done with passed arg  descriptor */
                 /* Things to note                   */  
                 /* we use dismiss() instead of pop() because this is a string */ 
                 /* which may be made up of a linked list of string blocks     */
                 /* Using pop would not free the sting blocks                  */
                 /* After dismiss() e_stack  points to descr which will receive RTNVAL */

/* now extract arguments from the past arg string */

  if (myval_len == 0) {
	  argCnt = 1;                       /* always one args */
	  SDMEArgArray[0] = NullString();   /* simply a null string */

  }else{ 

    if (IsArgMV != 0){             /* MV Arg set */
  /*  Get number of fields in ARG */
      argCnt = Dcount(myval_buffer, myFM);
	/* if we found more args than we can process, only extract what we can hold */
	    if (argCnt > SD_MAX_ARGS) {
		    argCnt = SD_MAX_ARGS;
      }
	
	    for (argIdx = 0; argIdx < argCnt; argIdx++) { 
        /* rem Extract allocates our buffer space */
	      SDMEArgArray[argIdx]	= Extract(myval_buffer, argIdx+1, 0, 0);
	    }
    } else {  /* MV Flag not set, */
        argCnt = 1;                       /* always one args */
        SDMEArgArray[0] = myval_buffer;   /* we just point to the value buffer created earlier */  
    }
  }	  
  
  switch (key) {
	  
	  case  SDEXT_TestIt: 
	/* simple test to see if any of this works, output args to stdout  */
	    for (argIdx = 0; argIdx < argCnt; argIdx++) {
	      printf("Arg %d of %d\r\n",argIdx+1, argCnt);
 	      printf("'%s'\r\n",SDMEArgArray[argIdx]);
	    }
      snprintf( myErrMsg, SD_ERR_MSG_LEN, "op_sdext() found %d args\n", argCnt);
      k_put_c_string(myErrMsg, e_stack);   /* sets as descr as type string and place the value in myErrMsg into it */
                                           /* this will then get transferred to RTNVAL via */
      e_stack++;	
      break; 

    case SD_SALT:
      char* mysalt = NULL;
      mysalt = sd_salt();   /* Create unique salt and return base64 encoded  (caller mustr free!!!)   */                 
      if (mysalt != NULL){
        k_put_c_string(mysalt, e_stack);   /* sets as descr as type string and place the value in it */
                                           /* this will then get transferred to RTNVAL */
        e_stack++;
        free(mysalt);
      }	else {
        sdme_err_rsp(SD_Mem_Err);          /* only possible error in sd_salt ? */
      }
      break; 


    case SD_KEYFROMPW:  
      char* mykey = NULL;
      if (argCnt != 2){
        sdme_err_rsp(SD_EXT_ARG_CNT);     /* we need 2 args for this to work */
        break;
      }
      
      mykey =  sd_KeyFromPW(SDMEArgArray[0], SDMEArgArray[1]);  /* create key from password in [0] and salt in [1] */
                                                                /* sd_KeyFromPW(char* mypassword, char* mysalt)    */
      if (mykey != NULL){
        k_put_c_string(mykey, e_stack);   /* sets as descr as type string and place the value in it */
                                           /* this will then get transferred to RTNVAL */
        e_stack++;
        sodium_free(mykey);                /* key buffer was allocated via sodium_malloc, free via sodium_free*/
      }	else {
        sdme_err_rsp(process.status);      /* eror set in process.status */
      }
      break;

    /* 20240808 mab embedding python? */
    #ifdef EMBED_PYTHON
    case SD_PyInit:  
    case SD_PyFinal:  
    case SD_IsPyInit: 
    case SD_PyRunStr:  
    case SD_PyRunFile: 
    case SD_PyGetAtt :
  /* embedding Python functions*/
      sdext_py(key, SDMEArgArray[0]);
      break;
    #endif  


    default:
      /* unknown key */
      sdme_err_rsp(SD_EXT_KEY_ERR);

  }
  
  /* release our arg Buffers  */
  for (argIdx = 0; argIdx < SD_MAX_ARGS; argIdx++) {
	  if (SDMEArgArray[argIdx] != NULL ){
	    free(SDMEArgArray[argIdx]);
	    SDMEArgArray[argIdx] = NULL;
	  }
  }  
  /* and the val buffer */	
  if (myval_buffer != NULL){
    if (IsArgMV != 0) {      /* rem if IsArgMV not set, we pointed DMEArgArray[0] to myval_buffer*/
	    free(myval_buffer);    /* do not want to attempt to free the memory again!!*/
    } 
  } 

  return;
}

char* NullString() {
  char* p;

  p = malloc(1);
  *p = '\0';
  return p;
}

/* generic error return with null response, setting process.status */
Private void sdme_err_rsp(int errNbr){
  char EmptyResp[1] = {'\0'}; /*  empty return message  */
  k_put_c_string(EmptyResp, e_stack); /* sets descr as type string, empty */
  e_stack++;
  process.status = errNbr;

}
