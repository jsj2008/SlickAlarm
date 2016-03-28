//
//  HttpClient.m
//  eNews
//
//  Created by kgi on 8/9/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "HttpClient.h"
#import "URLService.h"
#import "HttpClientPool.h"
#import "Parser.h"

@implementation HttpClient

@synthesize receivedData, statusCode, delegate, result, totalCount, identifier, requestType;
@synthesize tag;
- (id)init 
{
	if (self = [super init]) {
		[self reset];
	}
	return self;
}

- (void)dealloc 
{
	[identifier release];
	[result release];
	[connection release];
	[receivedData release];
    [tag release];
	[super dealloc];
}

- (void)reset 
{
	self.receivedData = [NSMutableData data];
	[connection release];
	connection = nil;
	statusCode = 0;	
	contentTypeIsXml = NO;
}

+ (NSString*)stringEncodedWithBase64:(NSString*)str
{
	static const char *tbl = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	
	const char *s = [str UTF8String];
	int length = [str length];
	char *tmp = malloc(length * 4 / 3 + 4);
	
	int i = 0;
	int n = 0;
	char *p = tmp;
	
	while (i < length) {
		n = s[i++];
		n *= 256;
		if (i < length) n += s[i];
		i++;
		n *= 256;
		if (i < length) n += s[i];
		i++;
		
		p[0] = tbl[((n & 0x00fc0000) >> 18)];
		p[1] = tbl[((n & 0x0003f000) >> 12)];
		p[2] = tbl[((n & 0x00000fc0) >>  6)];
		p[3] = tbl[((n & 0x0000003f) >>  0)];
		
		if (i > length) p[3] = '=';
		if (i > length + 1) p[2] = '=';
		
		p += 4;
	}
	
	*p = '\0';
	
	NSString *ret = [NSString stringWithCString:tmp encoding:NSUTF8StringEncoding];
	free(tmp);
	
	return ret;
}

+ (NSString*) stringOfAuthorizationHeaderWithUsername:(NSString*)username password:(NSString*)password 
{
    return [@"Basic " stringByAppendingString:[HttpClient stringEncodedWithBase64:
											   [NSString stringWithFormat:@"%@:%@", username, password]]];
}

- (NSMutableURLRequest*)makeRequest:(NSString*)url 
{
    NSLog(@"\n Sending request at %@", url);
	NSString *encodedUrl = (NSString*)CFURLCreateStringByAddingPercentEscapes(
																			  NULL, (CFStringRef)url, NULL, NULL, kCFStringEncodingUTF8);
	NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] init] autorelease];
	[request setURL:[NSURL URLWithString:encodedUrl]];
	[request setCachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData];
	[request setTimeoutInterval:TIMEOUT_SEC];
	[request setHTTPShouldHandleCookies:FALSE];
	[encodedUrl release];
	return request;
}

- (NSMutableURLRequest*)makeRequest:(NSString*)url username:(NSString*)username password:(NSString*)password 
{
	NSMutableURLRequest *request = [self makeRequest:url];
	[request setValue:[HttpClient stringOfAuthorizationHeaderWithUsername:username password:password]
   forHTTPHeaderField:@"Authorization"];
	return request;
}

- (void)prepareWithRequest:(NSMutableURLRequest*)request 
{
	// do nothing (for OAuthHttpClient)
}

- (void)requestGET:(NSString*)url
{
	[self reset];
	NSMutableURLRequest *request = [self makeRequest:url];
	[self prepareWithRequest:request];
	connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
}

- (void)requestPOST:(NSString*)url body:(NSString*)body
{
	[self reset];
	NSMutableURLRequest *request = [self makeRequest:url];
    [request setHTTPMethod:@"POST"];
	if (body) {
		[request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
	}
	[self prepareWithRequest:request];
	connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
}

- (void)requestGET:(NSString*)url username:(NSString*)username password:(NSString*)password
{
	[self reset];
	NSMutableURLRequest *request = [self makeRequest:url username:username password:password];
	connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
}

- (void)requestPOST:(NSString*)url body:(NSString*)body username:(NSString*)username password:(NSString*)password 
{
	[self reset];
	NSMutableURLRequest *request = [self makeRequest:url username:username password:password];
    [request setHTTPMethod:@"POST"];
	if (body) {
		[request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
	}
	connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
}

- (void)cancel 
{
	[connection cancel];
	[self reset];
	[self requestFailed:nil];
}

- (void)cancelDelegate
{
	delegate = nil;
	[self cancel];
}

- (void)requestSucceeded
{
	self.result = nil;
	self.totalCount = 0;
	
	if (statusCode == 200) {
		
		switch (requestType) {
            case SEARCHLOCATION_REQUEST: {
                
                self.result = [Parser parsePlaces:receivedData];
            }
                break;
                
			case GEONAME_REQUEST:{
				
				self.result = [Parser parsePlace:receivedData];
			}
				break;

			case WEATHER_REQUEST:{
				
				self.result = (NSObject *)[Parser parseWeather:receivedData];
			}
				break;
                
		}
		if (delegate)
			[delegate HttpClientSucceeded:self];
		[[HttpClientPool sharedInstance] releaseClient:self];
	}
	self.result = nil;
	self.totalCount = 0;
}

- (void)requestFailed:(NSError*)error 
{
	[delegate HttpClientFailed:self];
	[[HttpClientPool sharedInstance] releaseClient:self];
}

-(void)connection:(NSURLConnection*)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge*)challenge
{ 
	[[challenge sender] cancelAuthenticationChallenge:challenge]; 
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse 
{
	return nil;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response 
{
	statusCode = [(NSHTTPURLResponse*)response statusCode];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.receivedData appendData:data];	
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	[self requestSucceeded];
	[self reset];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError*) error {
	[self requestFailed:error];
	[self reset];
    
}

- (void) reqSearchPlaceByTerm:(NSString *)term {
	requestType = SEARCHLOCATION_REQUEST;
	reqUrl = [URLService reqSearchPlaceUrlByQuery:term];
	NSLog(@"Sending Request:%@", reqUrl);
	[self requestGET:reqUrl];
}

- (void) reqPlaceByLocation:(NSString *)location {
	requestType = GEONAME_REQUEST;
	reqUrl = [URLService reqPlaceForLocationUrlByQuery:location];
	NSLog(@"Sending Request:%@", reqUrl);
	[self requestGET:reqUrl];
}
- (void) reqWeatherByWoeID:(NSString *)woeID {
	requestType = WEATHER_REQUEST;
	reqUrl = [URLService reqWeatherUrlByWoeID:woeID andUnit:@"c"];
	NSLog(@"Sending Request:%@", reqUrl);
	[self requestGET:reqUrl];
}


@end
