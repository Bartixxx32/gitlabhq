require 'spec_helper'

describe API::Namespaces do
  let!(:unused_project) { create(:project) }
  let(:admin) { create(:admin) }
  let(:user) { create(:user) }
  let!(:group1) { create(:group) }
  let!(:group2) { create(:group, :nested) }

  describe "GET /namespaces" do
    context "when unauthenticated" do
      it "returns authentication error" do
        get api("/namespaces")
        expect(response).to have_gitlab_http_status(401)
      end
    end

    context "when authenticated as admin" do
      it "returns correct attributes" do
        get api("/namespaces", admin)

        group_kind_json_response = json_response.find { |resource| resource['kind'] == 'group' }
        user_kind_json_response = json_response.find { |resource| resource['kind'] == 'user' }

        expect(response).to have_gitlab_http_status(200)
        expect(response).to include_pagination_headers
        expect(group_kind_json_response.keys).to contain_exactly('id', 'kind', 'name', 'path', 'full_path',
                                                                 'parent_id', 'members_count_with_descendants', 'user_id')

        expect(user_kind_json_response.keys).to contain_exactly('id', 'kind', 'name', 'path', 'full_path', 'parent_id', 'user_id')
      end

      it "admin: returns an array of all namespaces" do
        get api("/namespaces", admin)

        expect(response).to have_gitlab_http_status(200)
        expect(response).to include_pagination_headers
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(Namespace.count)
      end

      it "admin: returns an array of matched namespaces" do
        get api("/namespaces?search=#{group2.name}", admin)

        expect(response).to have_gitlab_http_status(200)
        expect(response).to include_pagination_headers
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(1)
        expect(json_response.last['path']).to eq(group2.path)
        expect(json_response.last['full_path']).to eq(group2.full_path)
      end
    end

    context "when authenticated as a regular user" do
      it "returns correct attributes when user can admin group" do
        group1.add_owner(user)

        get api("/namespaces", user)

        owned_group_response = json_response.find { |resource| resource['id'] == group1.id }

        expect(owned_group_response.keys).to contain_exactly('id', 'kind', 'name', 'path', 'full_path',
                                                             'parent_id', 'members_count_with_descendants', 'user_id')
      end

      it "returns correct attributes when user cannot admin group" do
        group1.add_guest(user)

        get api("/namespaces", user)

        guest_group_response = json_response.find { |resource| resource['id'] == group1.id }

        expect(guest_group_response.keys).to contain_exactly('id', 'kind', 'name', 'path', 'full_path', 'parent_id', 'user_id')
      end

      it "user: returns an array of namespaces" do
        get api("/namespaces", user)

        expect(response).to have_gitlab_http_status(200)
        expect(response).to include_pagination_headers
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(1)
      end

      it "admin: returns an array of matched namespaces" do
        get api("/namespaces?search=#{user.username}", user)

        expect(response).to have_gitlab_http_status(200)
        expect(response).to include_pagination_headers
        expect(json_response).to be_an Array
        expect(json_response.length).to eq(1)
      end
    end
  end

  describe 'GET /namespaces/:id' do
    let(:owned_group) { group1 }
    let(:user2) { create(:user) }

    shared_examples 'can access namespace' do
      it 'returns namespace details' do
        get api("/namespaces/#{namespace_id}", request_actor)

        expect(response).to have_gitlab_http_status(200)

        expect(json_response['id']).to eq(requested_namespace.id)
        expect(json_response['path']).to eq(requested_namespace.path)
        expect(json_response['name']).to eq(requested_namespace.name)

        if namespace_kind == :user
          expect(json_response['user_id']).to eq(requested_namespace_owner.id)
        end
      end
    end

    shared_examples 'namespace reader' do
      let(:requested_namespace) { owned_group }

      before do
        owned_group.add_owner(request_actor)
      end

      context 'when namespace exists' do
        context 'when requested by ID' do
          context 'when requesting group' do
            let(:namespace_id) { owned_group.id }
            let(:namespace_kind) { :group }

            it_behaves_like 'can access namespace'
          end

          context 'when requesting personal namespace' do
            let(:namespace_id) { request_actor.namespace.id }
            let(:requested_namespace) { request_actor.namespace }
            let(:namespace_kind) { :user }
            let(:requested_namespace_owner) { request_actor }

            it_behaves_like 'can access namespace'
          end
        end

        context 'when requested by path' do
          context 'when requesting group' do
            let(:namespace_id) { owned_group.path }
            let(:namespace_kind) { :group }

            it_behaves_like 'can access namespace'
          end

          context 'when requesting personal namespace' do
            let(:namespace_id) { request_actor.namespace.path }
            let(:requested_namespace) { request_actor.namespace }
            let(:namespace_kind) { :user }
            let(:requested_namespace_owner) { request_actor }

            it_behaves_like 'can access namespace'
          end
        end
      end

      context "when namespace doesn't exist" do
        it 'returns not-found' do
          get api('/namespaces/9999', request_actor)

          expect(response).to have_gitlab_http_status(404)
        end
      end
    end

    context 'when unauthenticated' do
      it 'returns authentication error' do
        get api("/namespaces/#{group1.id}")

        expect(response).to have_gitlab_http_status(401)
      end
    end

    context 'when authenticated as regular user' do
      let(:request_actor) { user }

      context 'when requested namespace is not owned by user' do
        context 'when requesting group' do
          it 'returns not-found' do
            get api("/namespaces/#{group2.id}", request_actor)

            expect(response).to have_gitlab_http_status(404)
          end
        end

        context 'when requesting personal namespace' do
          it 'returns not-found' do
            get api("/namespaces/#{user2.namespace.id}", request_actor)

            expect(response).to have_gitlab_http_status(404)
          end
        end
      end

      context 'when requested namespace is owned by user' do
        it_behaves_like 'namespace reader'
      end
    end

    context 'when authenticated as admin' do
      let(:request_actor) { admin }

      context 'when requested namespace is not owned by user' do
        context 'when requesting group' do
          let(:namespace_id) { group2.id }
          let(:requested_namespace) { group2 }
          let(:namespace_kind) { :group }

          it_behaves_like 'can access namespace'
        end

        context 'when requesting personal namespace' do
          let(:namespace_id) { user2.namespace.id }
          let(:requested_namespace) { user2.namespace }
          let(:namespace_kind) { :user }
          let(:requested_namespace_owner) { user2 }

          it_behaves_like 'can access namespace'
        end
      end

      context 'when requested namespace is owned by user' do
        it_behaves_like 'namespace reader'
      end
    end
  end

  describe 'GET /namespaces/:id/projects' do
    let(:owned_group) { group1 }
    let(:user2) { create(:user) }

    shared_examples "can access namespace's projects" do
      it "returns namespace's projects details" do
        get api("/namespaces/#{namespace_id}/projects", request_actor)

        expect(response).to have_gitlab_http_status(200)
        expect(response).to include_pagination_headers

        expect(json_response).to be_a(Array)
        expect(json_response[0]['id']).to eq(expected_project.id)
        expect(json_response[0]['path']).to eq(expected_project.path)
      end
    end

    shared_examples "namespace's projects reader" do
      before do
        owned_group.add_owner(request_actor)
      end

      context 'when namespace exists' do
        context 'when requested by ID' do
          context 'when requesting group' do
            let(:namespace_id) { owned_group.id }
            let!(:expected_project) { create(:project, namespace: owned_group) }

            it_behaves_like "can access namespace's projects"
          end

          context 'when requesting personal namespace' do
            let(:namespace_id) { request_actor.namespace.id }
            let!(:expected_project) { create(:project, creator_id: request_actor.id, namespace: request_actor.namespace) }

            it_behaves_like "can access namespace's projects"
          end
        end

        context 'when requested by path' do
          context 'when requesting group' do
            let(:namespace_id) { owned_group.path }
            let!(:expected_project) { create(:project, namespace: owned_group) }

            it_behaves_like "can access namespace's projects"
          end

          context 'when requesting personal namespace' do
            let(:namespace_id) { request_actor.namespace.path }
            let!(:expected_project) { create(:project, creator_id: request_actor.id, namespace: request_actor.namespace) }

            it_behaves_like "can access namespace's projects"
          end
        end
      end

      context "when namespace doesn't exist" do
        it 'returns not-found' do
          get api('/namespaces/9999/projects', request_actor)

          expect(response).to have_gitlab_http_status(404)
        end
      end
    end

    context 'when unauthenticated' do
      it 'returns authentication error' do
        get api("/namespaces/#{group1.id}/projects")

        expect(response).to have_gitlab_http_status(401)
      end
    end

    context 'when authenticated as regular user' do
      let(:request_actor) { user }

      context 'when requested namespace is not owned by user' do
        context 'when requesting group' do
          it 'returns not-found' do
            get api("/namespaces/#{group2.id}/projects", request_actor)

            expect(response).to have_gitlab_http_status(404)
          end
        end

        context 'when requesting personal namespace' do
          it 'returns not-found' do
            get api("/namespaces/#{user2.namespace.id}/projects", request_actor)

            expect(response).to have_gitlab_http_status(404)
          end
        end
      end

      context 'when requested namespace is owned by user' do
        it_behaves_like "namespace's projects reader"
      end
    end

    context 'when authenticated as admin' do
      let(:request_actor) { admin }

      context 'when requested namespace is not owned by user' do
        context 'when requesting group' do
          let(:namespace_id) { group2.id }
          let!(:expected_project) { create(:project, namespace: group2) }

          it_behaves_like "can access namespace's projects"
        end

        context 'when requesting personal namespace' do
          let(:namespace_id) { user2.namespace.id }
          let!(:expected_project) { create(:project, creator_id: user2.id, namespace: user2.namespace) }

          it_behaves_like "can access namespace's projects"
        end
      end

      context 'when requested namespace is owned by user' do
        it_behaves_like "namespace's projects reader"
      end
    end
  end
end
