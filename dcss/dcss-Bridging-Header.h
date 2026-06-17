//
//  dcss-Bridging-Header.h
//  dcss (ASCII/console target — Target B)
//
//  Exposes the C console bridge + iOS helpers to Swift.
//

#import <Foundation/Foundation.h>

#include "console_bridge.h"
#import "path_utils.h"

// Provided by CDDA_iOS_main.mm — builds argv and calls crawl's DCSS_main.
int CDDA_iOS_main(const char *documentPath);
