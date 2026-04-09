-- local http = require('socket.http')
-- local ltn12 = require('ltn12')

-- local request_channel = love.thread.getChannel('modmulti_http_request')
-- local response_channel = love.thread.getChannel('modmulti_http_response')

-- while true do
--     local req = request_channel:demand()

--     if req and req.type == 'request' then
--         local response_chunks = {}

--         local http_req = {
--             url = req.url,
--             method = req.method or 'GET',
--             sink = ltn12.sink.table(response_chunks),
--             headers = req.headers,
--         }

--         if req.body then
--             http_req.source = ltn12.source.string(req.body)
--         end

--         http.TIMEOUT = req.timeout or 5

--         local ok, a, b, c = pcall(http.request, http_req)

--         if ok then
--             response_channel:push({
--                 requestId = req.requestId,
--                 ok = true,
--                 status_code = a,
--                 headers = b,
--                 status_line = c,
--                 body = table.concat(response_chunks),
--             })
--         else
--             response_channel:push({
--                 requestId = req.requestId,
--                 ok = false,
--                 error = a,
--                 status_code = 0,
--                 headers = {},
--                 status_line = '',
--                 body = '',
--             })
--         end
--     end
-- end