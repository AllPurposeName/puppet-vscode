require 'spec_helper'

describe 'message_router' do
  let(:subject_options) { nil }
  let(:subject) { PuppetLanguageServer::MessageRouter.new(subject_options) }

  describe '#documents' do
    it 'should respond to documents method' do
      expect(subject).to respond_to(:documents)
    end
  end

  describe '#receive_request' do
    let(:request_connection) { MockJSONRPCHandler.new() }
    let(:request_rpc_method) { nil }
    let(:request_params) { {} }
    let(:request_id) { 0 }
    let(:request) { PuppetLanguageServer::JSONRPCHandler::Request.new(
      request_connection,request_id,request_rpc_method,request_params) }

    before(:each) do
      allow(PuppetLanguageServer).to receive(:log_message)
    end

    # initialize - https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md#initialize
    context 'given an initialize request' do
      let(:request_rpc_method) { 'initialize' } 
      it 'should reply with capabilites' do
        expect(request).to receive(:reply_result).with(hash_including('capabilities'))

        subject.receive_request(request)
      end
    end

    # shutdown - https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md#shutdown
    context 'given a shutdown request' do
      let(:request_rpc_method) { 'shutdown' } 
      it 'should reply with nil' do
        expect(request).to receive(:reply_result).with(nil)

        subject.receive_request(request)
      end
    end

    context 'given a puppet/getVersion request' do
      let(:request_rpc_method) { 'puppet/getVersion' } 
      it 'should reply with the Puppet Version' do
        expect(request).to receive(:reply_result).with(hash_including('puppetVersion'))

        subject.receive_request(request)
      end
      it 'should reply with the Facter Version' do
        expect(request).to receive(:reply_result).with(hash_including('facterVersion'))

        subject.receive_request(request)
      end
      it 'should reply with the Language Server version' do
        expect(request).to receive(:reply_result).with(hash_including('languageServerVersion'))

        subject.receive_request(request)
      end
      it 'should reply with whether the facts are loaded' do
        expect(request).to receive(:reply_result).with(hash_including('factsLoaded'))

        subject.receive_request(request)
      end
      it 'should reply with whether the functions are loaded' do
        expect(request).to receive(:reply_result).with(hash_including('functionsLoaded'))

        subject.receive_request(request)
      end
      it 'should reply with whether the types are loaded' do
        expect(request).to receive(:reply_result).with(hash_including('typesLoaded'))

        subject.receive_request(request)
      end
    end

    context 'given a puppet/getResource request' do
      let(:request_rpc_method) { 'puppet/getResource' }
      let(:type_name) { 'user' }
      let(:title) { 'alice' }

      context 'and missing the typename' do
        let(:request_params) { {} }
        it 'should return an error string' do
          expect(request).to receive(:reply_result).with(hash_including('error'))

          subject.receive_request(request)
        end
      end

      context 'and resource face returns nil' do
        let(:request_params) { {
          'typename' => type_name,
        } }

        it 'should return data with an empty string' do
          expect(PuppetLanguageServer::PuppetHelper).to receive(:resource_face_get_by_typename).and_return(nil)
          expect(request).to receive(:reply_result).with(hash_including('data' => ''))

          subject.receive_request(request)
        end
      end

      context 'and only given a typename' do
        let(:request_params) { {
          'typename' => type_name,
        } }
        let(:resource_response) {[
          MockResource.new(type_name),
          MockResource.new(type_name)
        ]}

        context 'and resource face returns empty array' do
          it 'should return data with an empty string' do
            expect(PuppetLanguageServer::PuppetHelper).to receive(:resource_face_get_by_typename).and_return([])
            expect(request).to receive(:reply_result).with(hash_including('data' => ''))

            subject.receive_request(request)
          end
        end

        context 'and resource face returns array with at least 2 elements' do
          before(:each) do
            expect(PuppetLanguageServer::PuppetHelper).to receive(:resource_face_get_by_typename).with(type_name).and_return(resource_response)
          end

          it 'should call resource_face_get_by_typename' do
            subject.receive_request(request)
          end

          it 'should return data containing the type name' do
            expect(request).to receive(:reply_result).with(hash_including('data' => /#{type_name}/))

            subject.receive_request(request)
          end
        end
      end

      context 'and given a typename and title' do
        let(:request_params) { {
          'typename' => type_name,
          'title' => title,
        } }
        let(:resource_response) { MockResource.new(type_name,title) }

        context 'and resource face returns nil' do
          it 'should return data with an empty string' do
            expect(PuppetLanguageServer::PuppetHelper).to receive(:resource_face_get_by_typename_and_title).and_return(nil)
            expect(request).to receive(:reply_result).with(hash_including('data' => ''))

            subject.receive_request(request)
          end
        end

        context 'and resource face returns a resource' do
          before(:each) do
            expect(PuppetLanguageServer::PuppetHelper).to receive(:resource_face_get_by_typename_and_title).with(type_name,title).and_return(resource_response)
          end

          it 'should call resource_face_get_by_typename' do
            subject.receive_request(request)
          end

          it 'should return data containing the type name' do
            expect(request).to receive(:reply_result).with(hash_including('data' => /#{type_name}/))

            subject.receive_request(request)
          end

          it 'should return data containing the title' do
            expect(request).to receive(:reply_result).with(hash_including('data' => /#{title}/))

            subject.receive_request(request)
          end
        end
      end
    end

    context 'given a puppet/compileNodeGraph request' do
      let(:request_rpc_method) { 'puppet/compileNodeGraph' }
      let(:file_uri) { 'file:///something.pp' }
      let(:file_content) { 'some file content' }
      let(:dot_content) { 'some graph content' }
      let(:request_params) {{
        'external' => file_uri
      }}

      before(:each) do
        # Create fake document store
        subject.documents.clear
        subject.documents.set_document(file_uri,file_content)
      end

      context 'and an error during generation of the node graph' do
        before(:each) do
          expect(PuppetLanguageServer::PuppetParserHelper).to receive(:compile_to_pretty_relationship_graph).with(file_content).and_raise('MockError')
        end

        it 'should reply with the error text' do
          expect(request).to receive(:reply_result).with(hash_including('error' => /MockError/))

          subject.receive_request(request)
        end

        it 'should not reply with dotContent' do
          expect(request).to_not receive(:reply_result).with(hash_including('dotContent'))

          subject.receive_request(request)
        end
      end

      context 'and successfully generate the node graph' do
        let(:relationship_graph) { MockRelationshipGraph.new() }
        before(:each) do
          expect(PuppetLanguageServer::PuppetParserHelper).to receive(:compile_to_pretty_relationship_graph).with(file_content).and_return(relationship_graph)
        end

        context 'with one or more resources' do
          before(:each) do
            relationship_graph.vertices = [double('node1'),double('node2')]
            expect(relationship_graph).to receive(:to_dot).with(Hash).and_return(dot_content)
          end

          it 'should reply with dotContent' do
            expect(request).to receive(:reply_result).with(hash_including('dotContent' => dot_content))

            subject.receive_request(request)
          end

          it 'should not reply with error' do
            expect(request).to_not receive(:reply_result).with(hash_including('error'))

            subject.receive_request(request)
          end
        end

        context 'with zero resources' do
          before(:each) do
            relationship_graph.vertices = []
            expect(relationship_graph).to receive(:to_dot).with(Hash).never
          end

          it 'should reply with the error text' do
            expect(request).to receive(:reply_result).with(hash_including('error' => /no resources/))
  
            subject.receive_request(request)
          end
  
          it 'should not reply with dotContent' do
            expect(request).to_not receive(:reply_result).with(hash_including('dotContent'))
  
            subject.receive_request(request)
          end
        end
      end
    end

    # textDocument/completion - https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md#completion-request
    context 'given a textDocument/completion request' do
      let(:request_rpc_method) { 'textDocument/completion' }
      let(:line_num) { 1 }
      let(:char_num) { 2 }
      let(:request_params) {{
        'textDocument' => {
          'uri' => 'file:///something.pp'
        },
        'position' => {
          'line' => line_num,
          'character' => char_num,
        },
      }}

      it 'should call complete method on the Completion Provider' do
        expect(PuppetLanguageServer::CompletionProvider).to receive(:complete).with(Object,line_num,char_num).and_return('something')

        subject.receive_request(request)
      end

      context 'and an error occurs during completion' do
        before(:each) do
          expect(PuppetLanguageServer::CompletionProvider).to receive(:complete).and_raise('MockError')
        end

        it 'should log an error message' do
          expect(PuppetLanguageServer).to receive(:log_message).with(:error,/MockError/)

          subject.receive_request(request)
        end

        it 'should reply with a complete, empty response' do
          expect(request).to receive(:reply_result).with(hash_including('isIncomplete' => false, 'items' => []))

          subject.receive_request(request)
        end
      end
    end

    # completionItem/resolve - https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md#completion-request
    context 'given a completionItem/resolve request' do
      let(:request_rpc_method) { 'completionItem/resolve' }
      let(:request_params) {{
        'type' => 'keyword',
        'name' => 'class',
        'data' => '',
      }}

      it 'should call resolve method on the Completion Provider' do
        expect(PuppetLanguageServer::CompletionProvider).to receive(:resolve).and_return('something')

        subject.receive_request(request)
      end
      
      context 'and an error occurs during resolution' do
        before(:each) do
          expect(PuppetLanguageServer::CompletionProvider).to receive(:resolve).and_raise('MockError')
        end

        it 'should log an error message' do
          expect(PuppetLanguageServer).to receive(:log_message).with(:error,/MockError/)

          subject.receive_request(request)
        end

        it 'should reply with the same input params' do
          expect(request).to receive(:reply_result).with(request_params)

          subject.receive_request(request)
        end
      end
    end

    # textDocument/hover - https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md#textDocument_hover
    context 'given a textDocument/hover request' do
      let(:request_rpc_method) { 'textDocument/hover' }
      let(:line_num) { 1 }
      let(:char_num) { 2 }
      let(:request_params) {{
        'textDocument' => {
          'uri' => 'file:///something.pp'
        },
        'position' => {
          'line' => line_num,
          'character' => char_num,
        },
      }}

      it 'should call resolve method on the Hover Provider' do
        expect(PuppetLanguageServer::HoverProvider).to receive(:resolve).with(Object,line_num,char_num).and_return('something')

        subject.receive_request(request)
      end

      context 'and an error occurs during resolution' do
        before(:each) do
          expect(PuppetLanguageServer::HoverProvider).to receive(:resolve).and_raise('MockError')
        end

        it 'should log an error message' do
          expect(PuppetLanguageServer).to receive(:log_message).with(:error,/MockError/)

          subject.receive_request(request)
        end

        it 'should reply with nil for the contents' do
          expect(request).to receive(:reply_result).with(hash_including('contents' => nil))

          subject.receive_request(request)
        end
      end
    end

    context 'given an unknown request' do
      let(:request_rpc_method) { 'unknown_request_method' }

      it 'should log an error message' do
        expect(PuppetLanguageServer).to receive(:log_message).with(:error,"Unknown RPC method #{request_rpc_method}")

        subject.receive_request(request)
      end
    end
  end

  describe '#receive_notification' do
    let(:notification_method) { nil }
    let(:notification_params) { {} }

    # initialized - https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md#initialized
    context 'given an initialized notification' do
      let(:notification_method) { 'initialized' }

      it 'should log a message' do
        expect(PuppetLanguageServer).to receive(:log_message).with(:info,String)

        subject.receive_notification(notification_method, notification_params)
      end
    end

    # exit - https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md#exit-notification
    context 'given an exit notification' do
      let(:notification_method) { 'exit' }

      before(:each) do
        allow(subject).to receive(:close_connection)
      end

      it 'should log a message' do
        expect(PuppetLanguageServer).to receive(:log_message).with(:info,String)

        subject.receive_notification(notification_method, notification_params)
      end

      it 'should close the connection' do
        expect(subject).to receive(:close_connection)

        subject.receive_notification(notification_method, notification_params)
      end
    end

    # textDocument/didOpen - https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md#textDocument_didOpen
    context 'given an textDocument/didOpen notification' do
      let(:notification_method) { 'textDocument/didOpen' }
      let(:notification_params) { {
        'textDocument' => {
          'uri' => file_uri,
          'languageId' => 'puppet',
          'version' => 1,
          'text' => file_content,
        }
      }}
      let(:file_uri) { 'file:///newfile.pp' }
      let(:file_content) { 'file_content' }

      before(:each) do
        allow(PuppetLanguageServer::DocumentValidator).to receive(:validate).and_return([])
        allow(subject).to receive(:reply_diagnostics).and_return(true)
        subject.documents.clear
      end

      it 'should add the document to the document store' do
        subject.receive_notification(notification_method, notification_params)
        expect(subject.documents.document(file_uri)).to eq(file_content)
      end

      it 'should reply with diagnostic information on the file' do
        expect(subject).to receive(:reply_diagnostics).with(file_uri,[]).and_return(true)
        subject.receive_notification(notification_method, notification_params)
      end
    end

    # textDocument/didClose - https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md#didclosetextdocument-notification
    context 'given an textDocument/didClose notification' do
      let(:notification_method) { 'textDocument/didClose' }
      let(:notification_params) { {
        'textDocument' => { 'uri' => file_uri}
      }}
      let(:file_uri) { 'file:///somthing.pp' }
      let(:file_content) { 'file_content' }

      before(:each) do
        subject.documents.clear
        subject.documents.set_document(file_uri,file_content)
      end

      it 'should remove the document from the document store' do
        subject.receive_notification(notification_method, notification_params)
        expect(subject.documents.document(file_uri)).to be_nil
      end
    end

    # textDocument/didChange - https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md#didchangetextdocument-notification
    context 'given an textDocument/didChange notification' do
      let(:notification_method) { 'textDocument/didChange' }
      let(:file_uri) { 'file:///newfile.pp' }
      let(:new_file_content ) { 'new_file_content' }
      let(:file_content) { 'file_content' }

      before(:each) do
        allow(PuppetLanguageServer::DocumentValidator).to receive(:validate).and_return([])
        allow(subject).to receive(:reply_diagnostics).and_return(true)
        subject.documents.clear
      end

      context 'and a TextDocumentSyncKind of Full' do
        let(:notification_params) { {
          'textDocument' => {
            'uri' => file_uri,
            'version' => 2,
          },
          'contentChanges' => [
            {
              'range' => nil,
              'rangeLength' => nil,
              'text' => new_file_content,
            }
          ]
        }}

        it 'should update the document in the document store' do
          subject.receive_notification(notification_method, notification_params)
          expect(subject.documents.document(file_uri)).to eq(new_file_content)
        end

        it 'should reply with diagnostic information on the file' do
          expect(subject).to receive(:reply_diagnostics).with(file_uri,[]).and_return(true)
          subject.receive_notification(notification_method, notification_params)
        end
      end
    end

    # textDocument/didSave - https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md#didsavetextdocument-notification
    context 'given an textDocument/didSave notification' do
      let(:notification_method) { 'textDocument/didSave' }
      it 'should log a message' do
        expect(PuppetLanguageServer).to receive(:log_message).with(:info,String)

        subject.receive_notification(notification_method, notification_params)
      end
    end

    context 'given an unknown notification' do
      let(:notification_method) { 'unknown_notification_method' }

      it 'should log an error message' do
        expect(PuppetLanguageServer).to receive(:log_message).with(:error,"Unknown RPC notification #{notification_method}")

        subject.receive_notification(notification_method, notification_params)
      end
    end
  end
end
