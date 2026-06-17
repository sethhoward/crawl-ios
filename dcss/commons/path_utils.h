//
//  path_utils.h
//  CDDA
//
//  Created by Аполлов Юрий Андреевич on 09.03.2021.
//  Copyright © 2021 Аполлов Юрий Андреевич. All rights reserved.
//
#import <Foundation/Foundation.h>

#ifndef path_utils_h
#define path_utils_h

#ifdef __cplusplus
extern "C" {
#endif

NSURL* getICloudDocumentURL(void);
NSURL* getDocumentURL(void);

#ifdef __cplusplus
}
#endif

#endif /* path_utils_h */
