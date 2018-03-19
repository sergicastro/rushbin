require 'socket'

class MockServer
    def initialize
        @responses = []
    end

    def add_response(response)
        @responses << response
    end

    def read_request(socket)
        request = []
        while line = socket.gets
            request << line
            break if line =~ /^\s*$/
        end
        return request
    end

    def send_response(socket, response)
        socket.print "HTTP/1.1 #{response.status} #{response.message}\r\n" \
            "Content-Type: #{response.contenttype}\r\n" \
            "Content-Length: #{response.body.bytesize}\r\n" \
            "Connection: close\r\n"
        socket.print "\r\n"
        socket.print response.body
    end

    def run
        server = TCPServer.new('localhost', 4567)

        loop do
            socket = server.accept
            read_request(socket)
            if(@responses.length() > 0)
                response = @responses.first
                send_response(socket, response)
                @responses.delete(response)
                socket.close
            else
                raise Exception.new("No more resposes to send")
            end
        end
    end 
end

class Response
    attr_reader :body
    attr_reader :status
    attr_reader :message
    attr_reader :contenttype

    @body
    @status
    @message
    @contenttype

    def initialize(status="200", body="{}", message="OK", contenttype="application/json")
        @status = status
        @body = body
        @message = message
        @contenttype = contenttype
    end
end
