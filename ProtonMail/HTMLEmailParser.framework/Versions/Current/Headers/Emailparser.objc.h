// Objective-C API for talking to example.com/emailParser/emailParser Go package.
//   gobind -lang=objc example.com/emailParser/emailParser
//
// File is generated by gobind. Do not edit.

#ifndef __Emailparser_H__
#define __Emailparser_H__

@import Foundation;
#include "ref.h"
#include "Universe.objc.h"


FOUNDATION_EXPORT NSString* _Nonnull EmailparserExtractData(NSString* _Nullable content, BOOL removeQuotes);

#endif
