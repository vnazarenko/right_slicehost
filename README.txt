= RightScale Slicehost API Ruby Gem

Published by RightScale, Inc. under the MIT License.
For information about RightScale, see http://www.rightscale.com

== DESCRIPTION:

The RightScale Slicehost gem has been designed to provide a robust interface to Slicehost's existing API.

== FEATURES/PROBLEMS:

- Full programmatic access to the Slicehost API.
- Complete error handling: all operations check for errors and report complete
  error information by raising a SlicehostError.
- Persistent HTTP connections with robust network-level retry layer using
  Rightscale::HttpConnection. This includes socket timeouts and retries.
- Robust HTTP-level retry layer. Certain (user-adjustable) HTTP errors
  returned by Slicehost are classified as temporary errors.
  These errors are automaticallly retried using exponentially increasing intervals.
  The number of retries is user-configurable.
 
== INSTALL:

 sudo gem install right_slicehost

== LICENSE:

Copyright (c) 2007-2009 RightScale, Inc. 

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
